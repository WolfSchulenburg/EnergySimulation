{ ============================================================================
  uRCBuilder.pas

  Übersetzt ein TBuilding (Geometrie + Bauphysik) automatisch in ein
  TRCModel (thermisches Ersatzschaltbild). Für jede Fläche wird eine Kette
  von Widerständen erzeugt, die Raum und Außenluft (bzw. zwei Räume)
  verbindet:

    Außenwand:  Raum --Rsi--> [Material 1] --> [Material 2] --> ... --Rse--> Außenluft
    Innenwand:  Raum A --Rsi--> [Material 1] --> ... --Rsi--> Raum B

  Jeder in der Kette erzeugte Knoten trägt echte Wärmekapazität (aus der
  jeweiligen Materialschicht). Bewusst werden dabei *keine* zusätzlichen,
  masselosen "Oberflächenknoten" zwischen Rsi/Rse und der ersten/letzten
  Materialschicht eingefügt: TRCModel.Step() aktualisiert nur Knoten mit
  HeatCapacity > 0 (siehe uRCModel.pas), ein masseloser Zwischenknoten
  würde also nie auf seine tatsächliche Gleichgewichtstemperatur
  zulaufen und - in Kombination mit einem sehr kleinen Widerstand -
  sogar zu einer numerisch instabilen Simulation führen. Rsi und Rse
  gehen stattdessen direkt als eigene Widerstände in die Kette ein, ohne
  eigenen Knoten dazwischen.

  Jede Fläche mit einem gesetzten UValue (> 0) - nicht nur Fenster, sondern
  z. B. auch Wände/Dach/Boden, die nur über einen pauschalen U-Wert statt
  über einen Schichtaufbau beschrieben sind (siehe uBuildingGenerator.pas) -
  wird als einzelner Widerstand aus Rsi + 1/UValue + Rse modelliert. Das
  entspricht der im Gespräch eingeführten Vereinfachung für Fenster und wird
  hier verallgemeinert, weil grobe Gebäudebeschreibungen (Baujahr,
  Dämmstandard, ...) in aller Regel nur ein Ziel-U-Wert je Bauteiltyp liefern,
  keinen vollständigen Schichtaufbau.

  Für Wände mit Öffnungen wird die Nettofläche (NetArea = Area - Öffnungen)
  verwendet, damit die Fensterfläche nicht doppelt in die Wandfläche und den
  Fensterwiderstand eingeht. Die Öffnung selbst muss zusätzlich separat beim
  TBuilding registriert werden (Building.AddSurface), damit der Builder sie
  als eigene, parallele Fläche verarbeitet.

  Erdreichberührte Flächen (Kind = skGroundFloor/skGroundWall) werden nicht
  an die Außenluft, sondern an einen eigenen "ground"-Knoten angeschlossen,
  dessen Temperatur i. d. R. deutlich stabiler ist als die Außenlufttemperatur
  (grobe Näherung: die ungestörte Erdreichtemperatur folgt in erster Näherung
  der Jahresmitteltemperatur des Standorts) - siehe GroundTemperature.
  ============================================================================ }
unit uRCBuilder;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  uBuilding,
  uConstruction,
  uRCModel;

type

  TRCModelBuilder = class
  private
    FModel: TRCModel;
    FGroundTemperature: Double;

    procedure BuildRoom(Room: TRoom);
    procedure BuildSurface(Surface: TSurface);
    procedure BuildExteriorSurface(Surface: TSurface);
    procedure BuildInternalSurface(Surface: TSurface);
    procedure BuildVentilation(Room: TRoom);

    { Verbindet StartNode über Rsi, die Materialschichten der Fläche (bzw.
      den U-Wert-Widerstand, falls kein Schichtaufbau vorliegt) und Rsi/Rse
      mit EndNode. Wird für Außen- wie Innenflächen gleichermaßen verwendet. }
    procedure BuildSurfaceChain(Surface: TSurface; const IDPrefix: string;
      StartNode, EndNode: TRCNode; RStart, REnd: Double);

  public
    constructor Create;

    function Build(Building: TBuilding): TRCModel;

    { Feste Temperatur des "ground"-Knotens (°C), an den erdreichberührte
      Flächen angeschlossen werden. Muss vor Build() gesetzt werden, um
      wirksam zu sein; Default 10°C (grober, klimaunabhängiger Richtwert). }
    property GroundTemperature: Double read FGroundTemperature write FGroundTemperature;
  end;


function VentilationResistance(Volume: Double; AirChangeRate: Double): Double;

implementation

const
  RsiDefault = 0.13;  // innerer Wärmeübergangswiderstand, m²K/W
  RseDefault = 0.04;  // äußerer Wärmeübergangswiderstand, m²K/W

function VentilationResistance(Volume: Double; AirChangeRate: Double): Double;
const
  AirDensity = 1.2;       // kg/m³
  AirHeatCapacity = 1005.0; // J/(kg K)
var
  VolumeFlow: Double;
  Conductance: Double;
begin
  if (Volume <= 0) or (AirChangeRate <= 0) then
  begin
    Result := 1.0E100;
    Exit;
  end;

  VolumeFlow := AirChangeRate * Volume / 3600.0;
  Conductance := AirDensity * AirHeatCapacity * VolumeFlow;

  if Conductance <= 0 then
    Result := 1.0E100
  else
    Result := 1.0 / Conductance;
end;

{ TRCModelBuilder }

constructor TRCModelBuilder.Create;
begin
  inherited Create;
  FModel := nil;
  FGroundTemperature := 10.0;
end;

function TRCModelBuilder.Build(Building: TBuilding): TRCModel;
var
  I: Integer;
  GroundNode: TRCNode;
begin
  FModel := TRCModel.Create;

  { Außenluft }
  FModel.AddNode('outside', 'Außenluft', nkOutside);

  { Erdreich (fest, siehe GroundTemperature) }
  GroundNode := FModel.AddNode('ground', 'Erdreich', nkGround);
  GroundNode.Temperature := FGroundTemperature;

  { Räume }
  for I := 0 to Building.Rooms.Count - 1 do
    BuildRoom(TRoom(Building.Rooms[I]));

  { Flächen }
  for I := 0 to Building.Surfaces.Count - 1 do
    BuildSurface(TSurface(Building.Surfaces[I]));

  { Lüftung }
  for I := 0 to Building.Rooms.Count - 1 do
    BuildVentilation(TRoom(Building.Rooms[I]));

  Result := FModel;
  FModel := nil;
end;

procedure TRCModelBuilder.BuildRoom(Room: TRoom);
const
  DefaultMassCoupling = 0.0005; // K/W, entspricht einer großen, gut angekoppelten Fläche
var
  Node, MassNode: TRCNode;
  Coupling: Double;
begin
  Node := FModel.AddNode('room_' + Room.ID, Room.Name, nkRoom);

  { Wärmekapazität der Raumluft }
  Node.HeatCapacity := Room.Volume * 1.2 * 1005.0;
  Node.Temperature := 20.0;

  { Optionaler Massenknoten (Möbel, Estrich, innere Bauteilmassen, ...) }
  if Room.ThermalMassCapacity > 0 then
  begin
    MassNode := FModel.AddNode('mass_' + Room.ID, Room.Name + ' (Speichermasse)',
      nkMaterial);
    MassNode.HeatCapacity := Room.ThermalMassCapacity;
    MassNode.Temperature := 20.0;

    Coupling := Room.ThermalMassCoupling;
    if Coupling <= 0 then
      Coupling := DefaultMassCoupling;

    FModel.AddLink('mass_link_' + Room.ID, 'Speichermasse ' + Room.Name,
      Node, MassNode, Coupling, lkInternalTransfer);
  end;
end;

procedure TRCModelBuilder.BuildSurface(Surface: TSurface);
begin
  if Surface.IsExterior then
    BuildExteriorSurface(Surface)
  else
    BuildInternalSurface(Surface);
end;

procedure TRCModelBuilder.BuildSurfaceChain(Surface: TSurface;
  const IDPrefix: string; StartNode, EndNode: TRCNode; RStart, REnd: Double);
var
  PreviousNode, NewNode: TRCNode;
  Layer: TConstructionLayer;
  I, LayerCount: Integer;
  R, C, Area: Double;
begin
  Area := Surface.NetArea;
  if Area <= 0 then
    Area := Surface.Area;

  if Surface.UValue > 0 then
  begin
    { Kein Schichtaufbau, aber ein pauschaler U-Wert bekannt (Fenster, oder
      eine nur grob über den Dämmstandard beschriebene Wand/Dach/Boden):
      ein einziger Gesamtwiderstand aus Rsi + 1/U + Rse, ohne zusätzlichen
      (masselosen) Zwischenknoten. }
    FModel.AddLink(IDPrefix + '_U', 'U-Wert ' + Surface.Name,
      StartNode, EndNode,
      RStart / Area + 1.0 / (Surface.UValue * Area) + REnd / Area,
      lkWindow);
    Exit;
  end;

  LayerCount := 0;
  if Surface.Construction <> nil then
    LayerCount := Surface.Construction.LayerCount;

  if LayerCount = 0 then
  begin
    { Kein Schichtaufbau bekannt: nur die Übergangswiderstände }
    FModel.AddLink(IDPrefix + '_R', Surface.Name,
      StartNode, EndNode, (RStart + REnd) / Area, lkSurfaceResistance);
    Exit;
  end;

  PreviousNode := StartNode;

  for I := 0 to LayerCount - 1 do
  begin
    Layer := Surface.Construction.Layer(I);

    if I = 0 then
      R := RStart / Area + Layer.Resistance(Area)
    else
      R := Layer.Resistance(Area);

    if I < LayerCount - 1 then
    begin
      NewNode := FModel.AddNode(IDPrefix + '_layer_' + IntToStr(I),
        Layer.Material.Name, nkMaterial);

      C := Layer.Capacity(Area);
      NewNode.HeatCapacity := C;

      FModel.AddLink(IDPrefix + '_R_' + IntToStr(I), Layer.Material.Name,
        PreviousNode, NewNode, R, lkMaterialLayer);

      PreviousNode := NewNode;
    end
    else
    begin
      { letzte Schicht: direkt mit EndNode verbinden und dabei auch den
        äußeren Übergangswiderstand REnd mit einrechnen. Die Kapazität der
        letzten Schicht wird EndNode zugeschlagen, sofern EndNode selbst
        kein Material-, sondern ein Raum-/Außenluftknoten ist (der ohnehin
        schon eine sinnvolle eigene Kapazität hat) - wir legen sie daher
        stattdessen auf einen eigenen Knoten für die letzte Schicht, damit
        keine Wärmekapazität verloren geht. }
      NewNode := FModel.AddNode(IDPrefix + '_layer_' + IntToStr(I),
        Layer.Material.Name, nkMaterial);

      NewNode.HeatCapacity := Layer.Capacity(Area);

      FModel.AddLink(IDPrefix + '_R_' + IntToStr(I), Layer.Material.Name,
        PreviousNode, NewNode, R, lkMaterialLayer);

      FModel.AddLink(IDPrefix + '_Rend', Surface.Name,
        NewNode, EndNode, REnd / Area, lkSurfaceResistance);
    end;
  end;
end;

procedure TRCModelBuilder.BuildExteriorSurface(Surface: TSurface);
var
  RoomNode, OuterNode: TRCNode;
  Area: Double;
begin
  if (Surface.SideA = nil) or (Surface.SideA.Space = nil) then
    Exit;

  RoomNode := FModel.FindNode('room_' + Surface.SideA.Space.ID);

  if Surface.Kind in [skGroundFloor, skGroundWall] then
    OuterNode := FModel.FindNode('ground')
  else
    OuterNode := FModel.FindNode('outside');

  Area := Surface.NetArea;
  if Area <= 0 then
    Area := Surface.Area;

  if Area <= 0 then
    Exit;

  BuildSurfaceChain(Surface, Surface.ID, RoomNode, OuterNode,
    RsiDefault, RseDefault);
end;

procedure TRCModelBuilder.BuildInternalSurface(Surface: TSurface);
var
  RoomA, RoomB: TRCNode;
  Area: Double;
begin
  if (Surface.SideA = nil) or (Surface.SideB = nil) then
    Exit;

  if (Surface.SideA.Space = nil) or (Surface.SideB.Space = nil) then
    Exit;

  RoomA := FModel.FindNode('room_' + Surface.SideA.Space.ID);
  RoomB := FModel.FindNode('room_' + Surface.SideB.Space.ID);

  Area := Surface.NetArea;
  if Area <= 0 then
    Area := Surface.Area;

  if Area <= 0 then
    Exit;

  BuildSurfaceChain(Surface, Surface.ID, RoomA, RoomB,
    RsiDefault, RsiDefault);
end;

procedure TRCModelBuilder.BuildVentilation(Room: TRoom);
var
  RoomNode, OutsideNode: TRCNode;
  R: Double;
begin
  RoomNode := FModel.FindNode('room_' + Room.ID);
  OutsideNode := FModel.FindNode('outside');

  R := VentilationResistance(Room.Volume, Room.AirChangeRate);

  FModel.AddLink('vent_' + Room.ID, 'Lüftung ' + Room.Name,
    RoomNode, OutsideNode, R, lkVentilation);
end;

end.
