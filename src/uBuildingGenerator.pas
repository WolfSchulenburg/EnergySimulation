{ ============================================================================
  uBuildingGenerator.pas

  Erzeugt aus einer groben TBuildingDescription (Baujahr, Grundfläche bzw.
  Länge/Breite, Höhe, Stockwerke, Dachform, Fensteranteil, Dämmstandard, ...)
  ein vollständiges TBuilding, das wie jedes andere TBuilding (Demo-Gebäude,
  gbXML-Import) an uRCBuilder übergeben werden kann.

  Vereinfachungen (bewusst, für ein Überschlagstool):

  - EINE thermische Zone für das gesamte Gebäude, unabhängig von der Anzahl
    der Stockwerke. Geschossdecken/-böden zwischen den Stockwerken werden
    daher nicht einzeln modelliert; jedes Geschoss trägt aber mit seiner
    eigenen Außenwandfläche (Umfang * Geschosshöhe) zur Gesamtwandfläche
    bei, und das gesamte Luftvolumen (Grundfläche * Höhe * Stockwerke)
    geht in die Lüftungswärmeverluste ein.
  - RECHTECKIGER Grundriss. Sind nur Grundfläche, aber nicht Länge/Breite
    bekannt, wird ein quadratischer Grundriss angenommen.
  - Der Fensteranteil gilt gleichmäßig für alle vier Fassadenseiten und
    alle Geschosse.
  - Dachform wirkt nur über einen Flächenzuschlag auf die Dachfläche
    (Flachdach 1,0 / Satteldach 1,15 / Walmdach 1,20), nicht über eine
    tatsächliche 3D-Geometrie.
  - Für die Speichermasse wird ein mittelschwerer Baustandard angenommen
    (grober Richtwert 165 kJ/(m²K) bezogen auf die gesamte Geschossfläche,
    angelehnt an die in ISO 13790 übliche "medium"-Klasse), nicht aus den
    tatsächlichen Bauteilaufbauten hergeleitet.
  ============================================================================ }
unit uBuildingGenerator;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  uBuilding,
  uBuildingDescription,
  uInsulationStandards,
  uWeather;

{ Erzeugt das Gebäude. Warnings (falls übergeben) sammelt Hinweise zu
  Annahmen, die getroffen werden mussten (z. B. unbekannte Dachform). Der
  Aufrufer übernimmt den Besitz des zurückgegebenen TBuilding. }
function GenerateBuilding(const Description: TBuildingDescription;
  Warnings: TStringList): TBuilding;

{ Effektive U-Werte (Override aus der Beschreibung, sonst aus dem
  Dämmstandard). }
procedure GetEffectiveUValues(const Description: TBuildingDescription;
  out UWall, URoof, UFloor, UWindow: Double);

{ Effektive Luftwechselrate (Override, sonst aus dem Dämmstandard). }
function GetEffectiveAirChangeRate(const Description: TBuildingDescription): Double;

{ Grobe Abschätzung des g-Werts der Fenster aus ihrem U-Wert (je besser
  gedämmt, desto eher Mehrfachverglasung mit niedrigerem g-Wert). }
function EstimateWindowSolarGValue(UWindow: Double): Double;

{ Klimaprofil für die Jahresbilanz, aus der Standort-Jahresmitteltemperatur
  der Beschreibung abgeleitet (Amplitude/Tagesgang bleiben beim
  Mitteleuropa-Default). }
function ClimateFromDescription(const Description: TBuildingDescription): TClimateProfile;

{ Angenommene Erdreichtemperatur für erdreichberührte Flächen: näherungsweise
  die Standort-Jahresmitteltemperatur. }
function GroundTemperatureFromDescription(const Description: TBuildingDescription): Double;

implementation

const
  ThermalMassPerFloorArea = 165000.0; // J/(m²K), "mittelschwere" Bauweise (ISO 13790)

function RoofAreaMultiplier(const RoofShapeName: string; Warnings: TStringList): Double;
var
  N: string;
begin
  N := LowerCase(Trim(RoofShapeName));

  if (N = 'flachdach') or (N = 'flach') then
    Result := 1.00
  else if (N = 'satteldach') or (N = 'sattel') then
    Result := 1.15
  else if (N = 'walmdach') or (N = 'walm') then
    Result := 1.20
  else
  begin
    if Warnings <> nil then
      Warnings.Add(Format('Dachform "%s" nicht erkannt (erwartet Flachdach/Satteldach/Walmdach) - verwende Flachdach.', [RoofShapeName]));
    Result := 1.00;
  end;
end;

procedure GetEffectiveUValues(const Description: TBuildingDescription;
  out UWall, URoof, UFloor, UWindow: Double);
var
  Values: TInsulationValues;
begin
  Values := GetInsulationValues(EffectiveStandard(Description));

  if Description.UWallOverride > 0 then UWall := Description.UWallOverride
  else UWall := Values.UWall;

  if Description.URoofOverride > 0 then URoof := Description.URoofOverride
  else URoof := Values.URoof;

  if Description.UFloorOverride > 0 then UFloor := Description.UFloorOverride
  else UFloor := Values.UFloor;

  if Description.UWindowOverride > 0 then UWindow := Description.UWindowOverride
  else UWindow := Values.UWindow;
end;

function GetEffectiveAirChangeRate(const Description: TBuildingDescription): Double;
begin
  if Description.AirChangeRate > 0 then
    Result := Description.AirChangeRate
  else
    Result := GetInsulationValues(EffectiveStandard(Description)).AirChangeRate;
end;

function EstimateWindowSolarGValue(UWindow: Double): Double;
begin
  if UWindow >= 2.5 then
    Result := 0.78   // ältere Zweifachverglasung
  else if UWindow >= 1.3 then
    Result := 0.65   // Wärmeschutzverglasung
  else
    Result := 0.55;  // moderne Dreifachverglasung
end;

function ClimateFromDescription(const Description: TBuildingDescription): TClimateProfile;
begin
  Result := DefaultClimateProfile;
  Result.AnnualMeanTemperature := Description.SiteAnnualMeanTemperature;
end;

function GroundTemperatureFromDescription(const Description: TBuildingDescription): Double;
begin
  Result := Description.SiteAnnualMeanTemperature;
end;

function GenerateBuilding(const Description: TBuildingDescription;
  Warnings: TStringList): TBuilding;
var
  Zone: TRoom;
  Length, Width, FloorHeight: Double;
  RoofMultiplier: Double;
  UWall, URoof, UFloor, UWindow: Double;
  WindowGValue: Double;
  Floor: Integer;
  Building: TBuilding;
  RoofSurface, GroundSurface: TSurface;

  procedure AddFacadeWall(const FacadeName: string; FacadeLength, Azimuth: Double);
  var
    GrossArea, WindowArea: Double;
    Wall, Window: TSurface;
    IDPrefix: string;
  begin
    GrossArea := FacadeLength * FloorHeight;
    if GrossArea <= 0 then
      Exit;

    WindowArea := GrossArea * (Description.WindowRatioPercent / 100.0);

    IDPrefix := Format('wall_%s_f%d', [FacadeName, Floor]);

    Wall := TSurface.Create;
    Wall.ID := IDPrefix;
    Wall.Name := Format('%s-Wand, Geschoss %d', [FacadeName, Floor + 1]);
    Wall.Kind := skExteriorWall;
    Wall.IsExterior := True;
    Wall.Area := GrossArea;
    Wall.Orientation := Azimuth;
    Wall.Tilt := 90;
    Wall.UValue := UWall;
    Wall.SideA.Space := Zone;

    if WindowArea > 0 then
    begin
      Window := TSurface.Create;
      Window.ID := IDPrefix + '_win';
      Window.Name := Format('%s-Fenster, Geschoss %d', [FacadeName, Floor + 1]);
      Window.Kind := skWindow;
      Window.IsExterior := True;
      Window.IsTransparent := True;
      Window.Area := WindowArea;
      Window.Orientation := Azimuth;
      Window.Tilt := 90;
      Window.UValue := UWindow;
      Window.SolarGValue := WindowGValue;
      Window.ShadingFactor := 0.9; // grobe Pauschale für Laibung/Rahmen/leichte Verschattung
      Window.SideA.Space := Zone;

      Wall.AddOpening(Window);
    end
    else
      Window := nil;

    Building.AddSurface(Wall);
    if Window <> nil then
      Building.AddSurface(Window);
  end;

begin
  if Description.Length > 0 then
    Length := Description.Length
  else
    Length := Sqrt(Max(1.0, Description.FootprintArea));

  if Description.Width > 0 then
    Width := Description.Width
  else
    Width := Description.FootprintArea / Max(0.001, Length);

  FloorHeight := Description.FloorHeight;
  RoofMultiplier := RoofAreaMultiplier(Description.RoofShapeName, Warnings);

  GetEffectiveUValues(Description, UWall, URoof, UFloor, UWindow);
  WindowGValue := EstimateWindowSolarGValue(UWindow);

  Building := TBuilding.Create;
  Building.Name := Description.Name;

  Zone := TRoom.Create;
  Zone.ID := 'zone';
  Zone.Name := Description.Name;
  Zone.Volume := Length * Width * FloorHeight * Description.Floors;
  Zone.AirChangeRate := GetEffectiveAirChangeRate(Description);
  Zone.ThermalMassCapacity := ThermalMassPerFloorArea * Length * Width * Description.Floors;

  Building.AddRoom(Zone);

  for Floor := 0 to Description.Floors - 1 do
  begin
    AddFacadeWall('Nord', Length, 0.0);
    AddFacadeWall('Ost',  Width,  90.0);
    AddFacadeWall('Sued', Length, 180.0);
    AddFacadeWall('West', Width,  270.0);
  end;

  { Dach: nur oberstes Geschoss }
  if Length * Width > 0 then
  begin
    RoofSurface := TSurface.Create;
    RoofSurface.ID := 'roof';
    RoofSurface.Name := 'Dach (' + Description.RoofShapeName + ')';
    RoofSurface.Kind := skRoof;
    RoofSurface.IsExterior := True;
    RoofSurface.Area := Length * Width * RoofMultiplier;
    RoofSurface.Orientation := 0;
    RoofSurface.Tilt := 0;
    RoofSurface.UValue := URoof;
    RoofSurface.SideA.Space := Zone;
    Building.AddSurface(RoofSurface);
  end;

  { Bodenplatte: nur unterstes Geschoss, erdreichberührt }
  if Length * Width > 0 then
  begin
    GroundSurface := TSurface.Create;
    GroundSurface.ID := 'ground_floor';
    GroundSurface.Name := 'Bodenplatte';
    GroundSurface.Kind := skGroundFloor;
    GroundSurface.IsExterior := True;
    GroundSurface.Area := Length * Width;
    GroundSurface.Orientation := 0;
    GroundSurface.Tilt := 180;
    GroundSurface.UValue := UFloor;
    GroundSurface.SideA.Space := Zone;
    Building.AddSurface(GroundSurface);
  end;

  Result := Building;
end;

end.
