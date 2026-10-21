{ ============================================================================
  uGbXMLAnalysis.pas

  Fasst ein (typischerweise per uGbXML.pas importiertes) Mehrzonen-TBuilding
  zu EINER thermischen Zone zusammen - notwendig, weil der Rest dieses
  Projekts (uHeatBalance.pas, TRCSimulation/TRCHeatingController in
  uSimulation.pas) für genau eine beheizte Zone ausgelegt ist, siehe
  README, Abschnitt "Bekannte Vereinfachungen"/"Wie aus der Beschreibung
  ein Gebäude wird".

  Vorgehen (bewusste Vereinfachungen, siehe auch Warnungen zur Laufzeit):

  - Räume gelten als "beheizt", wenn ihre DesignTemperature (z. B. aus
    gbXML <Space><Temperature>) mindestens UnheatedThreshold beträgt, ODER
    wenn gar keine DesignTemperature bekannt ist (0 = "nicht angegeben",
    dann wird der Raum vorsichtshalber als beheizt angenommen statt
    stillschweigend ausgeschlossen). Nur beheizte Räume tragen Volumen und
    Fläche zur neuen Zone bei.
  - Nur AUSSENFLÄCHEN (IsExterior) beheizter Räume werden in die neue Zone
    übernommen; Innenwände zwischen zwei beheizten Räumen tragen zur
    Bilanz einer einzigen Zone nichts bei (bei gleicher Solltemperatur
    fließt durch sie im Mittel kein Nettowärmestrom). Außenflächen, die zu
    einem UNBEHEIZTEN Raum gehören (z. B. Kelleraußenwand), werden
    ebenfalls NICHT übernommen - das unterschätzt den realen Wärmeverlust
    über solche Pufferräume tendenziell etwas (in Wirklichkeit fließt über
    sie durchaus Wärme vom beheizten in den unbeheizten Bereich und von
    dort nach außen), ist aber realistischer, als den unbeheizten Raum
    fälschlich auf die Solltemperatur der Zone zu heizen.
  - Flächen mit Kind = skUnknown (z. B. gbXML surfaceType "Shade" -
    Verschattungselemente ohne thermische Funktion) werden nicht
    übernommen.
  - Luftwechselrate der neuen Zone: volumengewichteter Mittelwert der
    beheizten Räume (in der Praxis meist überall derselbe Standardwert,
    da gbXML-BlowerDoor-Werte häufig nicht belastbar gesetzt sind - siehe
    uGbXML.pas).
  - Speichermasse: derselbe pauschale Anhaltswert wie in
    uBuildingGenerator.pas (165 kJ/(m²K) bezogen auf die beheizte
    Geschossfläche) - auch wenn die gbXML-Datei unter Umständen echte
    Materialschichten (Dicke/Dichte/spezifische Wärme) enthält, werden
    diese hier (noch) nicht zu einer genaueren Speichermasse verrechnet.
  ============================================================================ }
unit uGbXMLAnalysis;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  uBuilding;

const
  DefaultUnheatedThreshold = 15.0; // °C

{ Erzeugt aus Source ein neues, unabhängiges TBuilding mit genau einem Raum
  (ID = ZoneID). Der Aufrufer übernimmt den Besitz des Ergebnisses; Source
  bleibt unverändert und muss weiterhin selbst freigegeben werden. }
function AggregateToSingleZone(Source: TBuilding; const ZoneID, ZoneName: string;
  UnheatedThreshold: Double; Warnings: TStringList): TBuilding;

implementation

const
  ThermalMassPerFloorArea = 165000.0; // J/(m²K), wie uBuildingGenerator.pas

function IsHeatedRoom(Room: TRoom; UnheatedThreshold: Double): Boolean;
begin
  Result := (Room.DesignTemperature <= 0) or (Room.DesignTemperature >= UnheatedThreshold);
end;

function AggregateToSingleZone(Source: TBuilding; const ZoneID, ZoneName: string;
  UnheatedThreshold: Double; Warnings: TStringList): TBuilding;

  procedure Warn(const Msg: string);
  begin
    if Warnings <> nil then
      Warnings.Add(Msg);
  end;

var
  NewBuilding: TBuilding;
  Zone: TRoom;
  I, J: Integer;
  Room: TRoom;
  Surface, NewSurface, SourceOpening, NewOpening: TSurface;
  OpeningObjects: TFPList; // Referenzen aller Flächen, die Öffnung einer anderen Fläche sind
  TotalVolume, TotalFloorArea, WeightedACH: Double;
  HeatedCount, UnheatedCount: Integer;
  CopiedCount, SkippedInteriorCount, SkippedUnheatedRoomCount, SkippedUnknownKindCount: Integer;
begin
  NewBuilding := TBuilding.Create;
  NewBuilding.Name := Source.Name;

  Zone := TRoom.Create;
  Zone.ID := ZoneID;
  Zone.Name := ZoneName;
  NewBuilding.AddRoom(Zone);

  { -- Volumen/Fläche/Luftwechselrate aus den beheizten Räumen -- }

  TotalVolume := 0;
  TotalFloorArea := 0;
  WeightedACH := 0;
  HeatedCount := 0;
  UnheatedCount := 0;

  for I := 0 to Source.Rooms.Count - 1 do
  begin
    Room := TRoom(Source.Rooms[I]);

    if IsHeatedRoom(Room, UnheatedThreshold) then
    begin
      Inc(HeatedCount);
      TotalVolume := TotalVolume + Room.Volume;
      TotalFloorArea := TotalFloorArea + Room.FloorArea;
      WeightedACH := WeightedACH + Room.AirChangeRate * Room.Volume;
    end
    else
    begin
      Inc(UnheatedCount);
      Warn(Format('Raum "%s" (%s, %.1f°C) unter der Schwelle von %.1f°C - als unbeheizt behandelt: weder sein Volumen noch seine Außenflächen fließen in die Bilanz ein.',
        [Room.Name, Room.ID, Room.DesignTemperature, UnheatedThreshold]));
    end;
  end;

  if HeatedCount = 0 then
    Warn('Kein Raum wurde als beheizt eingestuft - die Bilanz wird auf einem leeren Gebäude beruhen. Prüfe UnheatedThreshold bzw. die Space-Temperaturen der Quelldatei.');

  if TotalFloorArea <= 0 then
  begin
    Warn('Keine Geschossfläche aus den beheizten Räumen ableitbar - grob aus dem Volumen geschätzt (Volumen / 2,6 m).');
    TotalFloorArea := TotalVolume / 2.6;
  end;

  Zone.Volume := TotalVolume;
  Zone.FloorArea := TotalFloorArea;

  if TotalVolume > 0 then
    Zone.AirChangeRate := WeightedACH / TotalVolume
  else
    Zone.AirChangeRate := 0.5;

  Zone.ThermalMassCapacity := ThermalMassPerFloorArea * TotalFloorArea;

  { -- Außenflächen (samt Öffnungen) der beheizten Räume übernehmen -- }

  { Erst alle Flächen sammeln, die als Öffnung einer anderen Fläche geführt
    werden - die dürfen unten nicht nochmal als "eigenständige" Fläche
    verarbeitet werden (siehe uGbXML.ReadOpenings: eine Öffnung wird sowohl
    ihrer Trägerfläche als auch dem TBuilding direkt hinzugefügt). }
  OpeningObjects := TFPList.Create;
  try
    for I := 0 to Source.Surfaces.Count - 1 do
    begin
      Surface := TSurface(Source.Surfaces[I]);
      for J := 0 to Surface.OpeningCount - 1 do
        OpeningObjects.Add(Surface.Opening(J));
    end;

    CopiedCount := 0;
    SkippedInteriorCount := 0;
    SkippedUnheatedRoomCount := 0;
    SkippedUnknownKindCount := 0;

    for I := 0 to Source.Surfaces.Count - 1 do
    begin
      Surface := TSurface(Source.Surfaces[I]);

      if OpeningObjects.IndexOf(Surface) >= 0 then
        Continue; // wird über ihre Trägerfläche mitkopiert, siehe unten

      if not Surface.IsExterior then
      begin
        Inc(SkippedInteriorCount);
        Continue;
      end;

      if Surface.Kind = skUnknown then
      begin
        Inc(SkippedUnknownKindCount);
        Continue;
      end;

      if (Surface.SideA = nil) or (Surface.SideA.Space = nil) then
      begin
        Warn(Format('Fläche "%s" ohne bekannten Raum - übersprungen.', [Surface.ID]));
        Continue;
      end;

      if not IsHeatedRoom(Surface.SideA.Space, UnheatedThreshold) then
      begin
        Inc(SkippedUnheatedRoomCount);
        Continue;
      end;

      NewSurface := TSurface.Create;
      NewSurface.ID := Surface.ID;
      NewSurface.Name := Surface.Name;
      NewSurface.Kind := Surface.Kind;
      NewSurface.IsExterior := True;
      NewSurface.IsTransparent := Surface.IsTransparent;
      NewSurface.Area := Surface.Area;
      NewSurface.Orientation := Surface.Orientation;
      NewSurface.Tilt := Surface.Tilt;
      NewSurface.UValue := Surface.UValue;
      NewSurface.SolarGValue := Surface.SolarGValue;
      NewSurface.ShadingFactor := Surface.ShadingFactor;
      NewSurface.SourceID := Surface.SourceID;
      NewSurface.SourceFormat := Surface.SourceFormat;
      NewSurface.SideA.Space := Zone;

      NewBuilding.AddSurface(NewSurface);
      Inc(CopiedCount);

      for J := 0 to Surface.OpeningCount - 1 do
      begin
        SourceOpening := Surface.Opening(J);

        NewOpening := TSurface.Create;
        NewOpening.ID := SourceOpening.ID;
        NewOpening.Name := SourceOpening.Name;
        NewOpening.Kind := SourceOpening.Kind;
        NewOpening.IsExterior := True;
        NewOpening.IsTransparent := SourceOpening.IsTransparent;
        NewOpening.Area := SourceOpening.Area;
        NewOpening.Orientation := SourceOpening.Orientation;
        NewOpening.Tilt := SourceOpening.Tilt;
        NewOpening.UValue := SourceOpening.UValue;
        NewOpening.SolarGValue := SourceOpening.SolarGValue;
        NewOpening.ShadingFactor := SourceOpening.ShadingFactor;
        NewOpening.SourceID := SourceOpening.SourceID;
        NewOpening.SourceFormat := SourceOpening.SourceFormat;
        NewOpening.SideA.Space := Zone;

        NewSurface.AddOpening(NewOpening);
        NewBuilding.AddSurface(NewOpening);
      end;
    end;

  finally
    OpeningObjects.Free;
  end;

  Warn(Format('Einzonen-Zusammenfassung: %d von %d Räumen beheizt, %d Außenflächen übernommen (%d Innenflächen, %d Flächen unbeheizter Räume, %d Flächen unbekannter Art übersprungen).',
    [HeatedCount, HeatedCount + UnheatedCount, CopiedCount,
     SkippedInteriorCount, SkippedUnheatedRoomCount, SkippedUnknownKindCount]));

  Result := NewBuilding;
end;

end.
