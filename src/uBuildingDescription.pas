{ ============================================================================
  uBuildingDescription.pas

  Liest eine grobe, von Hand schreibbare Textbeschreibung eines Gebäudes
  ein (Zeilen der Form "Schlüssel: Wert", Kommentare mit # oder ;) und
  liefert sie als TBuildingDescription. uBuildingGenerator.pas erzeugt
  daraus ein TBuilding, das durch den Rest des Programms (RC-Builder,
  Simulation) unverändert weiterverarbeitet werden kann.

  Nur wenige Angaben sind zwingend - alles andere hat einen dokumentierten
  Default. Erkannte Schlüssel (deutsch, Umlaute in ae/oe/ue-Schreibweise
  ebenfalls erlaubt):

    Name                            beliebiger Text
    Baujahr                         Jahr, z. B. 1965
    Daemmstandard                   z. B. Altbau, EnEV2016, Passivhaus, KfW55
                                     (überschreibt die aus dem Baujahr
                                     abgeleitete Baualtersklasse)
    Grundflaeche                    m², alternativ Laenge + Breite
    Laenge, Breite                  m
    Hoehe                           m, Geschosshöhe (gilt für jedes Geschoss)
    Stockwerke                      Anzahl oberirdischer Geschosse
    Dachform                        Flachdach | Satteldach | Walmdach
    Fensteranteil                   % der Fassadenfläche je Himmelsrichtung
    Luftwechselrate                 1/h (überschreibt den Standard-Wert)
    Innentemperatur                 °C, Auslegungswert
    Aussentemperatur_Auslegung      °C, winterlicher Auslegungswert
    Standort_Jahresmitteltemperatur °C, für synthetisches Jahresklima und
                                     Erdreichtemperatur (wird ignoriert, wenn
                                     eine TRY-Datei angegeben ist - dann wird
                                     die Erdreichtemperatur aus deren echtem
                                     Jahresmittel abgeleitet)
    Standort_Breitengrad            °, für die Sonnenstandsberechnung
                                     (Default: 53.43° - Hamburg)
    Standort_Laengengrad            °, für die Sonnenstandsberechnung
                                     (Default: 10.37° - Hamburg)
    Standort_Zeitzone               Stunden zu UTC, z. B. 1 = MEZ (Default: 1)

    UWert_Wand, UWert_Dach, UWert_Boden, UWert_Fenster
                                     W/(m²K), überschreiben den Dämmstandard
                                     für die jeweilige Bauteilart

    TRY_Datei                       Pfad zu einer DWD-Testreferenzjahr-Datei
                                     (siehe uTRYImport.pas). Relative Pfade
                                     werden relativ zum Verzeichnis DIESER
                                     Beschreibungsdatei aufgelöst, nicht zum
                                     Arbeitsverzeichnis des Programms. Ist
                                     diese Angabe vorhanden UND die Datei
                                     lesbar, verwendet die Jahressimulation
                                     echte Stundenwerte statt des
                                     synthetischen Jahresklimas.

    GbXML_Datei                     Pfad zu einer gbXML-Datei (siehe
                                     uGbXML.pas/uGbXMLAnalysis.pas). Relative
                                     Pfade werden wie bei TRY_Datei relativ
                                     zu DIESER Beschreibungsdatei aufgelöst.
                                     Ist diese Angabe vorhanden UND die Datei
                                     lesbar, kommen Geometrie UND U-Werte aus
                                     der gbXML-Datei statt aus
                                     Grundfläche/Länge/Breite/Stockwerke/
                                     Dachform/Fensteranteil/Dämmstandard/
                                     Uwert_* - diese Schlüssel werden dann
                                     ignoriert (ein evtl. trotzdem
                                     angegebener Dämmstandard wird nur noch
                                     für die grobe Vergleichsspanne am Ende
                                     verwendet).

  Unbekannte Schlüssel und nicht interpretierbare Werte erzeugen eine
  Warnung (in der übergebenen Warnings-Liste), führen aber nicht zum
  Abbruch - fehlende Angaben werden durch plausible Defaults ersetzt, damit
  auch eine sehr knappe Beschreibung sofort ein Ergebnis liefert.
  ============================================================================ }
unit uBuildingDescription;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  uInsulationStandards;

type

  TBuildingDescription = record
    Name: string;
    SourceFileName: string;

    ConstructionYear: Integer;     // Baujahr, 0 = unbekannt

    HasStandardName: Boolean;
    Standard: TInsulationStandard; // aus Daemmstandard oder aus ConstructionYear

    Length: Double;                // m, 0 = aus FootprintArea ableiten (Quadrat angenommen)
    Width: Double;                 // m
    FootprintArea: Double;         // m², 0 = aus Length*Width ableiten

    FloorHeight: Double;           // m
    Floors: Integer;               // Anzahl Geschosse

    RoofShapeName: string;         // 'Flachdach' | 'Satteldach' | 'Walmdach'

    WindowRatioPercent: Double;    // % der Fassadenfläche je Seite

    AirChangeRate: Double;         // 1/h, <= 0 = aus Standard ableiten

    IndoorSetpoint: Double;             // °C
    DesignOutdoorTemperature: Double;   // °C
    SiteAnnualMeanTemperature: Double;  // °C

    { Standort für die Sonnenstandsberechnung (uSolar.pas); Default
      entspricht TSolarModel.Create (Hamburg), damit unveränderte
      Beschreibungsdateien exakt wie bisher simuliert werden. }
    Latitude: Double;   // °
    Longitude: Double;  // °
    TimeZone: Double;   // Stunden zu UTC

    { Pfad zu einer TRY-Datei (uTRYImport.pas), '' = keine - dann wird wie
      bisher das synthetische Jahresklima verwendet. Wird beim Einlesen
      relativ zum Verzeichnis der Beschreibungsdatei aufgelöst. }
    TRYFileName: string;

    { Pfad zu einer gbXML-Datei (uGbXML.pas/uGbXMLAnalysis.pas), '' = keine
      - dann wird wie bisher aus den Geometrie-Schlüsseln generiert
      (uBuildingGenerator.pas). Wird beim Einlesen relativ zum Verzeichnis
      der Beschreibungsdatei aufgelöst. }
    GbXMLFileName: string;

    { 0 = nicht gesetzt -> aus Standard ableiten }
    UWallOverride: Double;
    URoofOverride: Double;
    UFloorOverride: Double;
    UWindowOverride: Double;
  end;

function DefaultBuildingDescription: TBuildingDescription;

{ Liest die Beschreibung aus FileName. Alle Probleme (unbekannte Datei,
  nicht interpretierbare Zeilen/Werte) werden als Text in Warnings
  angehängt (falls übergeben); es wird immer eine vollständige, mit
  Defaults aufgefüllte Beschreibung zurückgegeben. }
function LoadBuildingDescription(const FileName: string;
  Warnings: TStringList): TBuildingDescription;

{ Effektiver Dämmstandard: HasStandardName ? Standard : aus ConstructionYear }
function EffectiveStandard(const Description: TBuildingDescription): TInsulationStandard;

implementation

function DefaultBuildingDescription: TBuildingDescription;
begin
  FillChar(Result, SizeOf(Result), 0);

  Result.Name := 'Unbenanntes Gebäude';
  Result.ConstructionYear := 0;
  Result.HasStandardName := False;
  Result.Standard := isAltbau;

  Result.Length := 0;
  Result.Width := 0;
  Result.FootprintArea := 100.0;

  Result.FloorHeight := 2.6;
  Result.Floors := 1;

  Result.RoofShapeName := 'Flachdach';
  Result.WindowRatioPercent := 15.0;

  Result.AirChangeRate := 0; // -> aus Standard

  Result.IndoorSetpoint := 20.0;
  Result.DesignOutdoorTemperature := -12.0;
  Result.SiteAnnualMeanTemperature := 9.5;

  { Entspricht TSolarModel.Create (uSolar.pas) - unveränderte
    Beschreibungsdateien liefern damit exakt dieselben Ergebnisse wie vor
    Einführung dieser Felder. }
  Result.Latitude := 53.43;
  Result.Longitude := 10.37;
  Result.TimeZone := 1.0;

  Result.TRYFileName := '';
  Result.GbXMLFileName := '';

  Result.UWallOverride := 0;
  Result.URoofOverride := 0;
  Result.UFloorOverride := 0;
  Result.UWindowOverride := 0;
end;

function EffectiveStandard(const Description: TBuildingDescription): TInsulationStandard;
begin
  if Description.HasStandardName then
    Result := Description.Standard
  else
    Result := StandardFromConstructionYear(Description.ConstructionYear);
end;

{ Akzeptiert sowohl '.' als auch ',' als Dezimaltrennzeichen. }
function ParseFloat(const S: string; out Value: Double): Boolean;
var
  Cleaned: string;
  FS: TFormatSettings;
begin
  Cleaned := Trim(S);
  Cleaned := StringReplace(Cleaned, ',', '.', [rfReplaceAll]);

  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;

  Result := TryStrToFloat(Cleaned, Value, FS);
end;

function NormalizeKey(const S: string): string;
begin
  Result := LowerCase(Trim(S));

  { Deutsche Umlaute in beiden gängigen Schreibweisen zulassen: wir
    normalisieren hier nur die ae/oe/ue-Schreibweise auf sich selbst und
    lassen echte UTF-8-Umlaute unverändert - der Vergleich in
    LoadBuildingDescription prüft beide Varianten explizit. }
end;

{ Entfernt einen Kommentar (";" oder "#" außerhalb des Schlüssels) am Ende
  einer Werte-Zeile. }
function StripInlineComment(const S: string): string;
var
  P: Integer;
begin
  Result := S;

  P := Pos(';', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);

  Result := Trim(Result);
end;

{ Einfache, plattformunabhängige Prüfung auf einen relativen Pfad (FPCs
  SysUtils stellt kein IsRelativePath bereit): beginnt weder mit dem
  Pfadtrennzeichen (Unix "/") noch mit einem Windows-Laufwerksbuchstaben
  ("C:\..."). }
function IsRelative(const Path: string): Boolean;
begin
  Result := True;

  if Path = '' then
    Exit;

  if Path[1] = PathDelim then
  begin
    Result := False;
    Exit;
  end;

  if (Length(Path) >= 2) and (Path[2] = ':') then
    Result := False;
end;

function LoadBuildingDescription(const FileName: string;
  Warnings: TStringList): TBuildingDescription;

  procedure Warn(const Msg: string);
  begin
    if Warnings <> nil then
      Warnings.Add(Msg);
  end;

var
  Lines: TStringList;
  I, ColonPos, LineNo: Integer;
  RawLine, Key, Value: string;
  NumValue: Double;
  Std: TInsulationStandard;
begin
  Result := DefaultBuildingDescription;
  Result.SourceFileName := FileName;
  Result.Name := ExtractFileName(FileName);

  if not FileExists(FileName) then
  begin
    Warn(Format('Datei "%s" nicht gefunden - verwende ausschließlich Defaultwerte.', [FileName]));
    Exit;
  end;

  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(FileName);
    except
      on E: Exception do
      begin
        Warn(Format('Datei "%s" konnte nicht gelesen werden: %s', [FileName, E.Message]));
        Exit;
      end;
    end;

    for I := 0 to Lines.Count - 1 do
    begin
      LineNo := I + 1;
      RawLine := Trim(Lines[I]);

      if RawLine = '' then
        Continue;

      if (RawLine[1] = '#') or (RawLine[1] = ';') then
        Continue;

      ColonPos := Pos(':', RawLine);
      if ColonPos <= 0 then
      begin
        Warn(Format('Zeile %d ignoriert (kein "Schlüssel: Wert"): "%s"', [LineNo, RawLine]));
        Continue;
      end;

      Key := NormalizeKey(Copy(RawLine, 1, ColonPos - 1));
      Value := StripInlineComment(Copy(RawLine, ColonPos + 1, MaxInt));

      if Value = '' then
      begin
        Warn(Format('Zeile %d: kein Wert zu "%s" angegeben, ignoriert.', [LineNo, Key]));
        Continue;
      end;

      if Key = 'name' then
        Result.Name := Value

      else if Key = 'baujahr' then
      begin
        if TryStrToInt(Trim(Value), Result.ConstructionYear) then
          { ok }
        else
          Warn(Format('Zeile %d: Baujahr "%s" ist keine Zahl, ignoriert.', [LineNo, Value]));
      end

      else if (Key = 'daemmstandard') or (Key = 'dämmstandard') then
      begin
        if TryStandardFromName(Value, Std) then
        begin
          Result.HasStandardName := True;
          Result.Standard := Std;
        end
        else
          Warn(Format('Zeile %d: Dämmstandard "%s" nicht erkannt (erwartet z. B. Altbau, EnEV2016, KfW55, Passivhaus) - ignoriert.', [LineNo, Value]));
      end

      else if (Key = 'laenge') or (Key = 'länge') then
      begin
        if ParseFloat(Value, NumValue) then Result.Length := NumValue
        else Warn(Format('Zeile %d: Länge "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if Key = 'breite' then
      begin
        if ParseFloat(Value, NumValue) then Result.Width := NumValue
        else Warn(Format('Zeile %d: Breite "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if (Key = 'grundflaeche') or (Key = 'grundfläche') then
      begin
        if ParseFloat(Value, NumValue) then Result.FootprintArea := NumValue
        else Warn(Format('Zeile %d: Grundfläche "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if (Key = 'hoehe') or (Key = 'höhe') or (Key = 'geschosshoehe') or (Key = 'geschosshöhe') then
      begin
        if ParseFloat(Value, NumValue) then Result.FloorHeight := NumValue
        else Warn(Format('Zeile %d: Höhe "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if (Key = 'stockwerke') or (Key = 'geschosse') then
      begin
        if not TryStrToInt(Trim(Value), Result.Floors) then
          Warn(Format('Zeile %d: Stockwerke "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if Key = 'dachform' then
        Result.RoofShapeName := Trim(Value)

      else if Key = 'fensteranteil' then
      begin
        if ParseFloat(Value, NumValue) then Result.WindowRatioPercent := NumValue
        else Warn(Format('Zeile %d: Fensteranteil "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if Key = 'luftwechselrate' then
      begin
        if ParseFloat(Value, NumValue) then Result.AirChangeRate := NumValue
        else Warn(Format('Zeile %d: Luftwechselrate "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if Key = 'innentemperatur' then
      begin
        if ParseFloat(Value, NumValue) then Result.IndoorSetpoint := NumValue
        else Warn(Format('Zeile %d: Innentemperatur "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if (Key = 'aussentemperatur_auslegung') or (Key = 'außentemperatur_auslegung') then
      begin
        if ParseFloat(Value, NumValue) then Result.DesignOutdoorTemperature := NumValue
        else Warn(Format('Zeile %d: Auslegungsaußentemperatur "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if (Key = 'standort_jahresmitteltemperatur') then
      begin
        if ParseFloat(Value, NumValue) then Result.SiteAnnualMeanTemperature := NumValue
        else Warn(Format('Zeile %d: Jahresmitteltemperatur "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if (Key = 'standort_breitengrad') or (Key = 'breitengrad') then
      begin
        if ParseFloat(Value, NumValue) then Result.Latitude := NumValue
        else Warn(Format('Zeile %d: Breitengrad "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if (Key = 'standort_laengengrad') or (Key = 'standort_längengrad') or (Key = 'laengengrad') then
      begin
        if ParseFloat(Value, NumValue) then Result.Longitude := NumValue
        else Warn(Format('Zeile %d: Längengrad "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if (Key = 'standort_zeitzone') or (Key = 'zeitzone') then
      begin
        if ParseFloat(Value, NumValue) then Result.TimeZone := NumValue
        else Warn(Format('Zeile %d: Zeitzone "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if (Key = 'try_datei') or (Key = 'wetterdatei') then
      begin
        { Relativer Pfad -> relativ zum Verzeichnis DIESER Beschreibungs-
          datei auflösen, nicht zum Arbeitsverzeichnis des Programms, damit
          eine Beschreibung samt zugehöriger TRY-Datei aus jedem Verzeichnis
          heraus aufgerufen werden kann. }
        if IsRelative(Trim(Value)) then
          Result.TRYFileName := ExtractFilePath(ExpandFileName(FileName)) + Trim(Value)
        else
          Result.TRYFileName := Trim(Value);
      end

      else if (Key = 'gbxml_datei') or (Key = 'gebaeude_gbxml') then
      begin
        if IsRelative(Trim(Value)) then
          Result.GbXMLFileName := ExtractFilePath(ExpandFileName(FileName)) + Trim(Value)
        else
          Result.GbXMLFileName := Trim(Value);
      end

      else if Key = 'uwert_wand' then
      begin
        if ParseFloat(Value, NumValue) then Result.UWallOverride := NumValue
        else Warn(Format('Zeile %d: UWert_Wand "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if Key = 'uwert_dach' then
      begin
        if ParseFloat(Value, NumValue) then Result.URoofOverride := NumValue
        else Warn(Format('Zeile %d: UWert_Dach "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if Key = 'uwert_boden' then
      begin
        if ParseFloat(Value, NumValue) then Result.UFloorOverride := NumValue
        else Warn(Format('Zeile %d: UWert_Boden "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else if Key = 'uwert_fenster' then
      begin
        if ParseFloat(Value, NumValue) then Result.UWindowOverride := NumValue
        else Warn(Format('Zeile %d: UWert_Fenster "%s" ist keine Zahl.', [LineNo, Value]));
      end

      else
        Warn(Format('Zeile %d: Schlüssel "%s" wird nicht erkannt und ignoriert.', [LineNo, Key]));
    end;

  finally
    Lines.Free;
  end;

  { Plausibilitätsprüfungen mit Defaultwert-Korrektur (statt Abbruch) }
  if (Result.Length <= 0) or (Result.Width <= 0) then
  begin
    if Result.FootprintArea <= 0 then
    begin
      Warn('Weder Grundfläche noch Länge/Breite plausibel angegeben - verwende 100 m².');
      Result.FootprintArea := 100.0;
    end;
  end
  else
    Result.FootprintArea := Result.Length * Result.Width;

  if Result.FloorHeight <= 0 then
  begin
    Warn('Geschosshöhe nicht plausibel, verwende 2,6 m.');
    Result.FloorHeight := 2.6;
  end;

  if Result.Floors <= 0 then
  begin
    Warn('Anzahl Stockwerke nicht plausibel, verwende 1.');
    Result.Floors := 1;
  end;

  if (Result.WindowRatioPercent < 0) or (Result.WindowRatioPercent > 90) then
  begin
    Warn(Format('Fensteranteil %.1f%% unplausibel, verwende 15%%.', [Result.WindowRatioPercent]));
    Result.WindowRatioPercent := 15.0;
  end;
end;

end.
