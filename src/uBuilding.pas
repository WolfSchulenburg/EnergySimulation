{ ============================================================================
  uBuilding.pas

  Das Gebäudemodell: Flächen (TSurface), Räume (TRoom) und das Gebäude
  (TBuilding) selbst. Eine TSurface ist dabei - wie im Entwurfsgespräch
  herausgearbeitet - keine "Eigenschaft" eines Raumes, sondern eine
  thermische Verbindung zwischen zwei Seiten (SideA/SideB): bei einer
  Außenfläche ist SideB nil (das bedeutet: "draußen"), bei einer Innenwand
  verbinden SideA und SideB zwei Räume.

  Eine Fläche kann Öffnungen (Fenster/Türen) enthalten (TSurface.Openings);
  NetArea liefert die um die Öffnungen reduzierte Fläche, die für die
  Wandkonstruktion selbst verwendet wird, während die Öffnung ihrerseits
  wieder eine eigene TSurface ist (mit eigenem U-Wert), die separat im
  Gebäude registriert wird.
  ============================================================================ }
unit uBuilding;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs,
  uGeometry,
  uConstruction;

type

  TRoom = class;

  { TSurfaceKind
    Vereinigt die im Gespräch verwendete einfache Einteilung (skWall,
    skWindow, ...) mit der feineren, am gbXML-Standard orientierten
    Einteilung, die beim Import gebraucht wird. }
  TSurfaceKind = (
    skUnknown,
    skWall,
    skExteriorWall,
    skInteriorWall,
    skGroundWall,
    skWindow,
    skSkylight,
    skDoor,
    skOpening,
    skFloor,
    skInteriorFloor,
    skGroundFloor,
    skCeiling,
    skRoof
  );

  { Woher stammt eine Fläche - von Hand modelliert, oder importiert? }
  TSurfaceSourceFormat = (sfManual, sfGbXML);

  { TSurfaceSide
    Eine Seite einer Fläche: entweder ein Raum (Space <> nil), oder die
    Außenwelt (IsOutside) bzw. das Erdreich (IsGround). }
  TSurfaceSide = class
  public
    Space: TRoom;
    Name: string;

    IsOutside: Boolean;
    IsGround: Boolean;

    constructor Create;
  end;


  { TSurface
    Eine ebene Fläche (Wand, Fenster, Tür, Dach, Boden, Decke). Geometrie
    (Polygon/Area/Orientation/Tilt) und Thermik (Construction bzw. UValue)
    sind getrennte, aber zusammengehörige Aspekte derselben Fläche. }
  TSurface = class
  private
    FOpenings: TObjectList;
  public
    ID: string;
    Name: string;

    Kind: TSurfaceKind;

    Polygon: TPolygon;

    SideA: TSurfaceSide;
    SideB: TSurfaceSide;

    Construction: TConstruction;

    IsExterior: Boolean;
    IsTransparent: Boolean;

    Orientation: Double;   // Grad, 0=N, 90=O, 180=S, 270=W
    Tilt: Double;          // Grad, 90 = senkrecht

    Area: Double;           // m², Bruttofläche (inkl. Öffnungen)

    { Für Fenster/Türen ohne Schichtaufbau: pauschaler U-Wert, W/(m²K) }
    UValue: Double;

    { Solarer Gesamtenergiedurchlassgrad (g-Wert) für transparente Flächen }
    SolarGValue: Double;

    { 1,0 = vollständig unverschattet, 0,0 = vollständig verschattet }
    ShadingFactor: Double;

    { Herkunft, z. B. für den Re-Import aus gbXML }
    SourceID: string;
    SourceFormat: TSurfaceSourceFormat;

    constructor Create;
    destructor Destroy; override;

    { Fügt eine Öffnung (Fenster/Tür) hinzu, die geometrisch Teil dieser
      Fläche ist. Die Öffnung wird selbst als eigenständige TSurface
      geführt (mit eigener Geometrie/Thermik) und muss zusätzlich beim
      TBuilding registriert werden. }
    procedure AddOpening(Opening: TSurface);
    function OpeningCount: Integer;
    function Opening(Index: Integer): TSurface;
    property Openings: TObjectList read FOpenings;

    { Nettofläche = Area minus der Fläche aller Öffnungen (nie negativ) }
    function NetArea: Double;

    { Übernimmt Area/Orientation/Tilt aus dem Polygon, sofern dieses
      (mindestens 3) Punkte besitzt. So kann eine Fläche entweder von Hand
      (Area/Orientation/Tilt direkt gesetzt) oder geometrisch (über Polygon)
      beschrieben werden. }
    procedure UpdateGeometry;
  end;


  { TRoom - ein Raum bzw. eine thermische Zone }
  TRoom = class
  public
    ID: string;
    Name: string;

    Volume: Double;          // m³, für die Berechnung der Luftmasse
    GeometryVolume: Double;  // m³, aus der Raumgeometrie hergeleitet (optional)

    FloorArea: Double;       // m², 0 = unbekannt (z. B. aus gbXML <Space><Area>)

    { Design-/Solltemperatur dieses Raums, °C. 0 = nicht bekannt/nicht
      gesetzt (Default: als beheizt behandeln). Manche gbXML-Exporte geben
      hier reale, raumspezifische Werte an (z. B. 8°C für einen
      unbeheizten Flur/Keller, 20°C für Wohnräume) - siehe
      uGbXMLAnalysis.AggregateToSingleZone. }
    DesignTemperature: Double;

    AirChangeRate: Double;   // 1/h, Luftwechselrate

    { Optionale, zusätzliche "effektive" Wärmekapazität für Möbel, Estrich,
      innere Bauteilmassen usw. (J/K), die nicht einzeln als Bauteilschicht
      modelliert werden - üblich, wenn ein Raum/Gebäude nur grob (z. B. aus
      einer Gebäudebeschreibung ohne Materialangaben) erzeugt wird. 0 = nicht
      verwendet. Wird von TRCModelBuilder als eigener, über einen kleinen
      festen Widerstand (ThermalMassCoupling) angekoppelter Knoten
      modelliert - die im Ingenieurwesen übliche vereinfachte Ein-Knoten-
      Abbildung der Gebäudemasse (vgl. das 5R1C-Modell aus ISO 13790). }
    ThermalMassCapacity: Double;

    { Ankoppelwiderstand des Massenknotens an die Raumluft, K/W. <= 0
      bedeutet: einen plausiblen Standardwert verwenden. }
    ThermalMassCoupling: Double;

    { Alle Flächen, die (auf einer ihrer beiden Seiten) an diesen Raum
      grenzen. Wird von TBuilding.AddSurface automatisch gepflegt. }
    Surfaces: TObjectList;

    constructor Create;
    destructor Destroy; override;

    procedure UpdateGeometry;
  end;


  { TBuilding - das gesamte Gebäude: eine Sammlung von Räumen und Flächen }
  TBuilding = class
  public
    Name: string;

    Rooms: TObjectList;
    Surfaces: TObjectList;

    constructor Create;
    destructor Destroy; override;

    procedure AddRoom(Room: TRoom);
    procedure AddSurface(Surface: TSurface);

    function FindRoom(const ID: string): TRoom;
    function FindSurface(const ID: string): TSurface;
  end;

implementation

{ TSurfaceSide }

constructor TSurfaceSide.Create;
begin
  inherited Create;
  Space := nil;
  IsOutside := False;
  IsGround := False;
end;

{ TSurface }

constructor TSurface.Create;
begin
  inherited Create;

  Polygon := TPolygon.Create;

  SideA := TSurfaceSide.Create;
  SideB := nil;

  FOpenings := TObjectList.Create(False);

  Kind := skUnknown;

  Area := 0;
  Orientation := 0;
  Tilt := 90;

  UValue := 0;
  SolarGValue := 0;
  ShadingFactor := 1.0;

  IsExterior := False;
  IsTransparent := False;

  SourceFormat := sfManual;
end;

destructor TSurface.Destroy;
begin
  Polygon.Free;
  SideA.Free;
  SideB.Free;
  FOpenings.Free;

  inherited Destroy;
end;

procedure TSurface.AddOpening(Opening: TSurface);
begin
  if Opening = nil then
    Exit;

  FOpenings.Add(Opening);
end;

function TSurface.OpeningCount: Integer;
begin
  Result := FOpenings.Count;
end;

function TSurface.Opening(Index: Integer): TSurface;
begin
  Result := TSurface(FOpenings[Index]);
end;

function TSurface.NetArea: Double;
var
  I: Integer;
begin
  Result := Area;

  for I := 0 to FOpenings.Count - 1 do
    Result := Result - TSurface(FOpenings[I]).Area;

  if Result < 0 then
    Result := 0;
end;

procedure TSurface.UpdateGeometry;
begin
  if (Polygon = nil) or (Polygon.Count < 3) then
    Exit;

  Area := Polygon.Area;
  Orientation := Polygon.Azimuth;
  Tilt := Polygon.Tilt;
end;

{ TRoom }

constructor TRoom.Create;
begin
  inherited Create;

  Surfaces := TObjectList.Create(False);

  Volume := 0;
  GeometryVolume := 0;
  FloorArea := 0;
  DesignTemperature := 0;
  AirChangeRate := 0.5;

  ThermalMassCapacity := 0;
  ThermalMassCoupling := 0;
end;

destructor TRoom.Destroy;
begin
  Surfaces.Free;
  inherited Destroy;
end;

procedure TRoom.UpdateGeometry;
begin
  if GeometryVolume > 0 then
    Volume := GeometryVolume;
end;

{ TBuilding }

constructor TBuilding.Create;
begin
  inherited Create;

  Rooms := TObjectList.Create(True);
  Surfaces := TObjectList.Create(True);
end;

destructor TBuilding.Destroy;
begin
  Surfaces.Free;
  Rooms.Free;

  inherited Destroy;
end;

procedure TBuilding.AddRoom(Room: TRoom);
begin
  Rooms.Add(Room);
end;

procedure TBuilding.AddSurface(Surface: TSurface);
begin
  Surfaces.Add(Surface);

  if (Surface.SideA <> nil) and (Surface.SideA.Space <> nil) then
    Surface.SideA.Space.Surfaces.Add(Surface);

  if (Surface.SideB <> nil) and (Surface.SideB.Space <> nil) then
    Surface.SideB.Space.Surfaces.Add(Surface);
end;

function TBuilding.FindRoom(const ID: string): TRoom;
var
  I: Integer;
begin
  Result := nil;

  for I := 0 to Rooms.Count - 1 do
    if SameText(TRoom(Rooms[I]).ID, ID) then
    begin
      Result := TRoom(Rooms[I]);
      Exit;
    end;
end;

function TBuilding.FindSurface(const ID: string): TSurface;
var
  I: Integer;
begin
  Result := nil;

  for I := 0 to Surfaces.Count - 1 do
    if SameText(TSurface(Surfaces[I]).ID, ID) then
    begin
      Result := TSurface(Surfaces[I]);
      Exit;
    end;
end;

end.
