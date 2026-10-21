{ ============================================================================
  uConstruction.pas

  Materialien und Bauteilaufbauten (Konstruktionen). Eine TConstruction ist
  ein Schichtaufbau aus TConstructionLayer-Objekten (Material + Dicke), aus
  dem später (in uRCBuilder) der thermische Widerstand und die
  Wärmekapazität jeder Schicht berechnet werden.
  ============================================================================ }
unit uConstruction;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs;

type

  { TMaterial - ein Baustoff mit den für die Thermik nötigen Kennwerten }
  TMaterial = class
  public
    Name: string;

    Lambda: Double;        // Wärmeleitfähigkeit, W/(m K)
    Density: Double;       // Rohdichte, kg/m³
    HeatCapacity: Double;  // spezifische Wärmekapazität, J/(kg K)
  end;


  { TConstructionLayer - eine Materialschicht bestimmter Dicke innerhalb
    eines Bauteilaufbaus. }
  TConstructionLayer = class
  public
    Material: TMaterial;
    Thickness: Double;     // m

    constructor Create(AMaterial: TMaterial; AThickness: Double);

    { Wärmedurchlasswiderstand dieser Schicht für die gegebene Fläche, K/W }
    function Resistance(Area: Double): Double;

    { Wärmekapazität dieser Schicht für die gegebene Fläche, J/K }
    function Capacity(Area: Double): Double;
  end;


  { TConstruction - ein kompletter Bauteilaufbau (z. B. "Außenwand") aus
    mehreren Schichten, von innen nach außen. }
  TConstruction = class
  private
    FLayers: TObjectList;
  public
    Name: string;

    constructor Create;
    destructor Destroy; override;

    procedure AddLayer(Material: TMaterial; Thickness: Double);

    function LayerCount: Integer;
    function Layer(Index: Integer): TConstructionLayer;
  end;

implementation

{ TConstructionLayer }

constructor TConstructionLayer.Create(AMaterial: TMaterial; AThickness: Double);
begin
  inherited Create;
  Material := AMaterial;
  Thickness := AThickness;
end;

function TConstructionLayer.Resistance(Area: Double): Double;
begin
  if (Area <= 0) or (Material = nil) or (Material.Lambda <= 0) then
  begin
    Result := 0;
    Exit;
  end;

  Result := Thickness / (Material.Lambda * Area);
end;

function TConstructionLayer.Capacity(Area: Double): Double;
begin
  if (Area <= 0) or (Material = nil) then
  begin
    Result := 0;
    Exit;
  end;

  Result := Material.Density * Thickness * Area * Material.HeatCapacity;
end;

{ TConstruction }

constructor TConstruction.Create;
begin
  inherited Create;
  FLayers := TObjectList.Create(True);
end;

destructor TConstruction.Destroy;
begin
  FLayers.Free;
  inherited Destroy;
end;

procedure TConstruction.AddLayer(Material: TMaterial; Thickness: Double);
begin
  FLayers.Add(TConstructionLayer.Create(Material, Thickness));
end;

function TConstruction.LayerCount: Integer;
begin
  Result := FLayers.Count;
end;

function TConstruction.Layer(Index: Integer): TConstructionLayer;
begin
  Result := TConstructionLayer(FLayers[Index]);
end;

end.
