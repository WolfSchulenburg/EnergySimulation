{ ============================================================================
  Analyse.lpr

  Liest eine oder mehrere grobe Gebäudebeschreibungen (Textdateien, siehe
  uBuildingDescription.pas und die Beispiele in data/) ein, erzeugt daraus
  jeweils ein Gebäude (uBuildingGenerator.pas) und liefert eine
  überschlägliche Wärmebilanz:

    - eine stationäre Auslegungsheizlast (Transmission + Lüftung bei
      winterlicher Auslegungsaußentemperatur), analog einem groben
      Kurzverfahren nach DIN EN 12831
    - eine dynamische Jahressimulation (5-Minuten-Schritte intern stabil
      integriert, hier mit 1-Stunden-Auflösung ausgewertet), aus der die
      tatsächlich vom Heizungsregler eingebrachte Jahres-Heizenergie und der
      spezifische Heizwärmebedarf (kWh/(m²a)) bestimmt werden. Standardmäßig
      mit einem synthetischen Jahresklima; ist in der Beschreibungsdatei
      "TRY_Datei: ..." angegeben, werden stattdessen echte DWD-TRY-
      Stundenwerte verwendet (siehe uTRYImport.pas)

  Die Geometrie kommt standardmäßig aus den einfachen Grundflaeche/Laenge/
  Breite/Stockwerke/Dachform/Fensteranteil-Angaben der Beschreibungsdatei
  (uBuildingGenerator.pas). Ist stattdessen "GbXML_Datei: ..." angegeben,
  werden Geometrie UND reale Bauteil-U-Werte aus einer gbXML-Datei
  importiert (uGbXML.pas) und zu einer Zone zusammengefasst
  (uGbXMLAnalysis.pas) - für eine Wärmebilanz des tatsächlichen, nicht nur
  eines generischen Gebäudes.

  Jedes übergebene Gebäude wird einzeln analysiert; am Ende steht eine
  Vergleichstabelle aller Gebäude.

  Aufruf:
    Analyse <gebaeude1.txt> [gebaeude2.txt ...]
    Analyse                  (ohne Argumente: die Beispiele in data/)
  ============================================================================ }
program Analyse;

{$mode objfpc}{$H+}

uses
  SysUtils, DateUtils, Math, Classes,
  uBuilding,
  uRCModel,
  uRCBuilder,
  uSimulation,
  uWeather,
  uInsulationStandards,
  uBuildingDescription,
  uBuildingGenerator,
  uHeatBalance,
  uTRYImport,
  uGbXML,
  uGbXMLAnalysis;

type
  TResultRow = record
    Name: string;
    StandardText: string;
    DesignHeatLoadKW: Double;
    AnnualDemandKWhPerM2a: Double;
  end;

var
  Results: array of TResultRow;
  ResultCount: Integer;

procedure AddResultRow(const Row: TResultRow);
begin
  SetLength(Results, ResultCount + 1);
  Results[ResultCount] := Row;
  Inc(ResultCount);
end;

{ Kürzt einen String auf MaxLen Zeichen (mit "..." als Hinweis auf die
  Kürzung), damit feste Spaltenbreiten in Format() garantiert eingehalten
  werden -- lange Gebäudenamen sollen die Vergleichstabelle nicht mehr
  zum Verrutschen bringen. }
function Truncated(const S: string; MaxLen: Integer): string;
var
  CutLen: Integer;
begin
  if Length(S) <= MaxLen then
  begin
    Result := S;
    Exit;
  end;
  CutLen := MaxLen - 3;
  if CutLen < 1 then CutLen := 1;
  { Strings sind hier UTF-8-kodiert (Umlaute etc.); Copy() schneidet nach
    Bytes, nicht nach Zeichen. Falls der Schnitt mitten in einem
    Mehrbyte-Zeichen landet (Fortsetzungsbyte 10xxxxxx), die Grenze
    zurückverschieben, damit kein kaputtes Zeichen entsteht. }
  while (CutLen > 1) and (Ord(S[CutLen + 1]) and $C0 = $80) do
    Dec(CutLen);
  Result := Copy(S, 1, CutLen) + '...';
end;

procedure PrintSeparator;
begin
  WriteLn(StringOfChar('-', 70));
end;

procedure AnalyseBuilding(const FileName: string);
var
  Warnings: TStringList;
  Description: TBuildingDescription;
  Building: TBuilding;
  Builder: TRCModelBuilder;
  Model: TRCModel;
  Simulation: TRCSimulation;
  Climate: TClimateProfile;
  GroundTemperature: Double;
  UWall, URoof, UFloor, UWindow: Double;
  Load: TDesignHeatLoadResult;
  UsableFloorArea, SpecificDemand: Double;
  LowBenchmark, HighBenchmark: Double;
  I: Integer;
  Surface: TSurface;
  CurrentTime, StartTime: TDateTime;
  StepHours: Double;
  Steps: Integer;
  Row: TResultRow;
  Standard: TInsulationStandard;
  HasMeaningfulStandard: Boolean;
  TRYYear: TTRYYear;
  UsingTRYData: Boolean;
  UsingGbXML: Boolean;
  GbXMLImporter: TgbXMLImporter;
  RawBuilding: TBuilding;
  J: Integer;
begin
  WriteLn;
  PrintSeparator;
  WriteLn('Gebäudebeschreibung: ', FileName);
  PrintSeparator;

  Warnings := TStringList.Create;
  try
    Description := LoadBuildingDescription(FileName, Warnings);

    { TRY-Datei laden, falls angegeben - vor der Warnungsausgabe, damit
      etwaige Probleme beim TRY-Import zusammen mit den übrigen Hinweisen
      zur Beschreibungsdatei erscheinen. Schlägt der Import fehl, fällt
      die Simulation weiter unten automatisch auf das synthetische
      Jahresklima zurück (LoadTRYYear hat dazu bereits eine Warnung
      hinterlassen). }
    UsingTRYData := False;
    if Description.TRYFileName <> '' then
      UsingTRYData := LoadTRYYear(Description.TRYFileName, TRYYear, Warnings);

    { gbXML-Geometrie laden, falls angegeben - aus demselben Grund wie bei
      TRY_Datei oben vor der Warnungsausgabe. Schlägt der Import fehl,
      bleibt Building vorerst ungesetzt und wird weiter unten wie gewohnt
      aus den Beschreibungs-Schlüsseln generiert. }
    UsingGbXML := False;
    Building := nil;
    if Description.GbXMLFileName <> '' then
    begin
      GbXMLImporter := TgbXMLImporter.Create;
      RawBuilding := TBuilding.Create;
      try
        if GbXMLImporter.LoadFromFile(Description.GbXMLFileName, RawBuilding) then
        begin
          for J := 0 to GbXMLImporter.Messages.Count - 1 do
            Warnings.Add('[gbXML] ' + GbXMLImporter.Messages[J]);

          Building := AggregateToSingleZone(RawBuilding, 'zone', Description.Name,
            DefaultUnheatedThreshold, Warnings);
          UsingGbXML := True;
        end
        else
        begin
          for J := 0 to GbXMLImporter.Messages.Count - 1 do
            Warnings.Add('[gbXML] ' + GbXMLImporter.Messages[J]);
          Warnings.Add(Format('gbXML-Datei "%s" konnte nicht geladen werden - falle auf generierte Geometrie zurück.',
            [Description.GbXMLFileName]));
        end;
      finally
        RawBuilding.Free;
        GbXMLImporter.Free;
      end;
    end;

    if Warnings.Count > 0 then
    begin
      WriteLn('Hinweise beim Einlesen:');
      for I := 0 to Warnings.Count - 1 do
        WriteLn('  - ', Warnings[I]);
      WriteLn;
    end;

    Standard := EffectiveStandard(Description);
    { Ohne echten Baujahr-/Dämmstandard-Bezug ist die Vergleichsspanne am
      Ende (GetTypicalSpecificDemandRange) nicht aussagekräftig - das
      betrifft nur gbXML-Gebäude ohne zusätzlich angegebenen Baujahr/
      Daemmstandard, bei denen die realen U-Werte direkt aus der Datei
      kommen. }
    HasMeaningfulStandard := Description.HasStandardName or
      (Description.ConstructionYear > 0) or (not UsingGbXML);

    WriteLn(Format('Name:                 %s', [Description.Name]));

    if UsingGbXML then
    begin
      WriteLn(Format('Geometrie:            aus gbXML-Datei "%s"', [ExtractFileName(Description.GbXMLFileName)]));
      if HasMeaningfulStandard then
        WriteLn(Format('Dämmstandard:         %s (nur für die Vergleichsspanne unten - U-Werte kommen aus der Datei)',
          [StandardName(Standard)]));
    end
    else
    begin
      if Description.ConstructionYear > 0 then
        WriteLn(Format('Baujahr:              %d', [Description.ConstructionYear]))
      else
        WriteLn('Baujahr:              unbekannt');
      WriteLn(Format('Dämmstandard:         %s', [StandardName(Standard)]));
      WriteLn(Format('Grundfläche:          %.1f m²', [Description.FootprintArea]));
      WriteLn(Format('Geschosshöhe:         %.2f m, Stockwerke: %d', [Description.FloorHeight, Description.Floors]));
      WriteLn(Format('Dachform:             %s', [Description.RoofShapeName]));
      WriteLn(Format('Fensteranteil:        %.0f %%', [Description.WindowRatioPercent]));
    end;

    WriteLn(Format('Standort:             %.2f° N, %.2f° O, Zeitzone UTC+%.0f',
      [Description.Latitude, Description.Longitude, Description.TimeZone]));
    if UsingTRYData then
      WriteLn(Format('Wetterdaten:          TRY-Datei "%s" (%d von %d Stunden, Jahresmittel %.1f°C)',
        [ExtractFileName(Description.TRYFileName), TRYYear.FilledHours, HoursPerYear, AverageTemperature(TRYYear)]))
    else
      WriteLn('Wetterdaten:          synthetisches Jahresklima');
    WriteLn;

    if not UsingGbXML then
    begin
      GetEffectiveUValues(Description, UWall, URoof, UFloor, UWindow);
      WriteLn('Verwendete U-Werte (W/(m²K)):');
      WriteLn(Format('  Wand:   %.2f   Dach: %.2f   Boden: %.2f   Fenster: %.2f',
        [UWall, URoof, UFloor, UWindow]));
      WriteLn(Format('  Luftwechselrate: %.2f 1/h', [GetEffectiveAirChangeRate(Description)]));
      WriteLn;
    end;

    { Gebäude erzeugen, falls nicht schon aus gbXML übernommen }
    if not UsingGbXML then
      Building := GenerateBuilding(Description, Warnings);

    try
      if UsingGbXML then
        UsableFloorArea := TRoom(Building.Rooms[0]).FloorArea
      else
        UsableFloorArea := Description.FootprintArea * Description.Floors;

      WriteLn('Flächenübersicht:');
      WriteLn(Format('  %-28s %10s %10s', ['Bauteil', 'Fläche m²', 'U W/m²K']));
      for I := 0 to Building.Surfaces.Count - 1 do
      begin
        Surface := TSurface(Building.Surfaces[I]);
        WriteLn(Format('  %-28s %10.2f %10.2f', [Truncated(Surface.Name, 28), Surface.Area, Surface.UValue]));
      end;
      WriteLn(Format('  Beheiztes Luftvolumen: %.1f m³', [TRoom(Building.Rooms[0]).Volume]));
      WriteLn;

      { RC-Modell. Erdreichtemperatur: bei echten TRY-Daten aus deren
        tatsächlichem Jahresmittel abgeleitet (belastbarer als die von Hand
        geschätzte Standort_Jahresmitteltemperatur), sonst wie bisher aus
        der Beschreibung. }
      if UsingTRYData then
        GroundTemperature := AverageTemperature(TRYYear)
      else
        GroundTemperature := GroundTemperatureFromDescription(Description);

      Builder := TRCModelBuilder.Create;
      Builder.GroundTemperature := GroundTemperature;
      Model := Builder.Build(Building);
      Builder.Free;

      try
        { Stationäre Auslegungsheizlast }
        Load := EstimateDesignHeatLoad(Model, 'room_zone',
          Description.IndoorSetpoint, Description.DesignOutdoorTemperature,
          GroundTemperature);

        WriteLn('Stationäre Auslegungsheizlast');
        WriteLn(Format('  (bei %.1f°C innen / %.1f°C außen / %.1f°C Erdreich):',
          [Description.IndoorSetpoint, Description.DesignOutdoorTemperature, GroundTemperature]));
        WriteLn(Format('  Transmission (Außenluft): %8.0f W', [Load.TransmissionLossOutside]));
        WriteLn(Format('  Transmission (Erdreich):  %8.0f W', [Load.TransmissionLossGround]));
        WriteLn(Format('  Lüftung:                  %8.0f W', [Load.VentilationLoss]));
        WriteLn(Format('  Summe (Heizlast):         %8.0f W  (%.1f kW)',
          [Load.TotalHeatLoad, Load.TotalHeatLoad / 1000.0]));
        WriteLn;

        { Jahressimulation }
        Simulation := TRCSimulation.Create(Building, Model, 'zone');
        try
          Simulation.Solar.Latitude := Description.Latitude;
          Simulation.Solar.Longitude := Description.Longitude;
          Simulation.Solar.TimeZone := Description.TimeZone;

          if UsingTRYData then
          begin
            Simulation.UseTRYData := True;
            Simulation.TRYYear := TRYYear;
          end
          else
          begin
            Climate := ClimateFromDescription(Description);
            Simulation.UseSeasonalClimate := True;
            Simulation.Climate := Climate;
          end;

          Simulation.Heating.Setpoint := Description.IndoorSetpoint;
          Simulation.Heating.DeadBand := 0.5;
          { Großzügig bemessen, damit der Regler die Solltemperatur auch am
            Auslegungspunkt zuverlässig hält und die Jahressumme wirklich
            die energetische Bilanz abbildet statt durch Leistungsmangel
            künstlich verringert zu werden. }
          Simulation.Heating.MaxPower := Max(500.0, 2.5 * Load.TotalHeatLoad);

          Simulation.TimeStepSeconds := 3600.0; // 1 h - intern trotzdem stabil unterschritten

          StartTime := EncodeDateTime(2026, 1, 1, 0, 0, 0, 0);
          StepHours := 1.0;
          Steps := Round(365 * 24 / StepHours);

          for I := 0 to Steps - 1 do
          begin
            CurrentTime := StartTime + I * (StepHours / 24.0);
            Simulation.Step(CurrentTime);
          end;

          SpecificDemand := SpecificHeatingDemand(
            Simulation.TotalHeatingEnergyKWh, UsableFloorArea);

          if UsingTRYData then
            WriteLn(Format('Jahressimulation (TRY-Wetterdaten "%s", Jahresmittel %.1f°C)',
              [ExtractFileName(Description.TRYFileName), AverageTemperature(TRYYear)]))
          else
            WriteLn('Jahressimulation (synthetisches Klima, Jahresmittel ',
              Description.SiteAnnualMeanTemperature:0:1, '°C)');
          WriteLn(Format('  Jahres-Heizenergie:       %8.0f kWh', [Simulation.TotalHeatingEnergyKWh]));
          WriteLn(Format('  Beheizte Geschossfläche:  %8.1f m²', [UsableFloorArea]));
          WriteLn(Format('  Spez. Heizwärmebedarf:    %8.1f kWh/(m²a)', [SpecificDemand]));

          if HasMeaningfulStandard then
          begin
            GetTypicalSpecificDemandRange(Standard, LowBenchmark, HighBenchmark);
            WriteLn(Format('  Grobe Vergleichsspanne für "%s": %.0f - %.0f kWh/(m²a)',
              [StandardName(Standard), LowBenchmark, HighBenchmark]));

            if (SpecificDemand >= LowBenchmark * 0.5) and (SpecificDemand <= HighBenchmark * 1.5) then
              WriteLn('  -> liegt in plausibler Größenordnung für diesen Dämmstandard.')
            else
              WriteLn('  -> weicht deutlich von der groben Vergleichsspanne ab - Eingaben prüfen.');
          end
          else
            WriteLn('  (kein Baujahr/Dämmstandard angegeben - keine Vergleichsspanne verfügbar; die U-Werte stammen direkt aus der gbXML-Datei.)');

          Row.Name := Description.Name;
          if HasMeaningfulStandard then
            Row.StandardText := StandardName(Standard)
          else
            Row.StandardText := 'gbXML (kein Standard angegeben)';
          Row.DesignHeatLoadKW := Load.TotalHeatLoad / 1000.0;
          Row.AnnualDemandKWhPerM2a := SpecificDemand;
          AddResultRow(Row);

        finally
          Simulation.Free;
        end;

      finally
        Model.Free;
      end;

    finally
      Building.Free;
    end;

  finally
    Warnings.Free;
  end;
end;

var
  Files: array of string;
  I: Integer;

begin
  if ParamCount = 0 then
  begin
    WriteLn('Kein Gebäude angegeben - analysiere die Beispiele in data/.');
    WriteLn('Aufruf: Analyse <gebaeude1.txt> [gebaeude2.txt ...]');

    SetLength(Files, 5);
    Files[0] := 'data/gebaeude_altbau.txt';
    Files[1] := 'data/gebaeude_neubau.txt';
    Files[2] := 'data/gebaeude_passivhaus.txt';
    Files[3] := 'data/gebaeude_mit_trywetter.txt';
    Files[4] := 'data/gebaeude_aus_gbxml.txt';
  end
  else
  begin
    SetLength(Files, ParamCount);
    for I := 1 to ParamCount do
      Files[I - 1] := ParamStr(I);
  end;

  ResultCount := 0;
  SetLength(Results, 0);

  for I := 0 to High(Files) do
    AnalyseBuilding(Files[I]);

  WriteLn;
  PrintSeparator;
  WriteLn('Vergleich aller analysierten Gebäude');
  PrintSeparator;
  WriteLn(Format('  %-30s %-32s %10s %14s',
    ['Gebäude', 'Standard', 'Heizlast', 'Bedarf']));
  WriteLn(Format('  %-30s %-32s %10s %14s',
    ['', '', '(kW)', '(kWh/m²a)']));
  for I := 0 to ResultCount - 1 do
    WriteLn(Format('  %-30s %-32s %10.1f %14.1f',
      [Truncated(Results[I].Name, 30), Truncated(Results[I].StandardText, 32),
       Results[I].DesignHeatLoadKW, Results[I].AnnualDemandKWhPerM2a]));
end.
