{ ============================================================================
  uRCModel.pas

  Das eigentliche thermische Ersatzschaltbild: Knoten (TRCNode) mit
  Temperatur und Wärmekapazität, verbunden durch Widerstände (TRCLink).
  TRCModel.Step() integriert das Netz einen Zeitschritt weiter (explizites
  Euler-Verfahren).

  Wichtig: Die erste, im Gespräch gezeigte Fassung von Step() aktualisierte
  die Knotentemperaturen sofort während der Schleife über die Links - das
  Ergebnis hing dadurch von der Reihenfolge der Links ab. Das Gespräch
  identifiziert das selbst als Fehler und ersetzt Step() durch die hier
  verwendete synchrone Variante: zuerst werden alle Wärmeflüsse mit den
  *alten* Temperaturen berechnet, und erst danach werden alle Knoten
  gleichzeitig aktualisiert.
  ============================================================================ }
unit uRCModel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs;

type

  TRCNodeKind = (
    nkUnknown,
    nkRoom,
    nkOutside,
    nkGround,
    nkSurface,
    nkMaterial
  );

  TRCNode = class
  public
    ID: string;
    Name: string;

    Kind: TRCNodeKind;

    Temperature: Double;   // °C
    HeatCapacity: Double;  // J/K, 0 = fester Knoten (Temperatur wird nicht integriert)
    HeatInput: Double;     // W, externe Wärmequelle an diesem Knoten

    constructor Create;
  end;


  TRCLinkKind = (
    lkUnknown,
    lkSurfaceResistance,
    lkMaterialLayer,
    lkWindow,
    lkVentilation,
    lkInternalTransfer
  );

  TRCLink = class
  public
    ID: string;
    Name: string;

    Kind: TRCLinkKind;

    NodeA: TRCNode;
    NodeB: TRCNode;

    Resistance: Double;   // K/W
    HeatFlow: Double;     // W, zuletzt berechneter Fluss von A nach B
  end;


  TRCModel = class
  private
    FNodes: TObjectList;
    FLinks: TObjectList;

    procedure StepOnce(DeltaTime: Double);
  public
    constructor Create;
    destructor Destroy; override;

    function AddNode(const ID, Name: string; Kind: TRCNodeKind): TRCNode;
    function AddLink(const ID, Name: string; A, B: TRCNode;
      Resistance: Double; Kind: TRCLinkKind): TRCLink;

    function FindNode(const ID: string): TRCNode;

    procedure ClearHeatInputs;

    { Ein Zeitschritt des expliziten Euler-Verfahrens, synchron: alle
      Wärmeflüsse werden zunächst mit den alten Temperaturen bestimmt,
      danach werden alle Knoten gleichzeitig fortgeschrieben.

      DeltaTime wird intern in mehrere kleinere Teilschritte (siehe
      MaxSubStepSeconds) zerlegt: ein Netz aus dünnen, hochleitfähigen
      Materialschichten (z. B. wenige mm Putz) ergibt sehr kleine
      Widerstände zwischen Knoten mit nennenswerter Wärmekapazität: die
      explizite Integration wäre bei einem einzelnen 5-Minuten-Schritt
      numerisch instabil (die Temperatur würde aufschwingen statt sich
      anzugleichen). Die Zerlegung in genügend kleine Teilschritte behebt
      das, ohne dass Aufrufer sich um die Stabilität kümmern müssen. }
    procedure Step(DeltaTime: Double);

    function NodeCount: Integer;
    function LinkCount: Integer;
    function Node(Index: Integer): TRCNode;
    function Link(Index: Integer): TRCLink;

    property Nodes: TObjectList read FNodes;
    property Links: TObjectList read FLinks;
  end;

implementation

{ TRCNode }

constructor TRCNode.Create;
begin
  inherited Create;

  Temperature := 20.0;
  HeatCapacity := 0.0;
  HeatInput := 0.0;
  Kind := nkUnknown;
end;

{ TRCModel }

constructor TRCModel.Create;
begin
  inherited Create;

  FNodes := TObjectList.Create(True);
  FLinks := TObjectList.Create(True);
end;

destructor TRCModel.Destroy;
begin
  FLinks.Free;
  FNodes.Free;

  inherited Destroy;
end;

function TRCModel.AddNode(const ID, Name: string; Kind: TRCNodeKind): TRCNode;
begin
  Result := TRCNode.Create;

  Result.ID := ID;
  Result.Name := Name;
  Result.Kind := Kind;

  FNodes.Add(Result);
end;

function TRCModel.AddLink(const ID, Name: string; A, B: TRCNode;
  Resistance: Double; Kind: TRCLinkKind): TRCLink;
begin
  Result := TRCLink.Create;

  Result.ID := ID;
  Result.Name := Name;
  Result.NodeA := A;
  Result.NodeB := B;
  Result.Resistance := Resistance;
  Result.Kind := Kind;

  FLinks.Add(Result);
end;

function TRCModel.FindNode(const ID: string): TRCNode;
var
  I: Integer;
  N: TRCNode;
begin
  Result := nil;

  for I := 0 to FNodes.Count - 1 do
  begin
    N := TRCNode(FNodes[I]);

    if SameText(N.ID, ID) then
    begin
      Result := N;
      Exit;
    end;
  end;
end;

procedure TRCModel.ClearHeatInputs;
var
  I: Integer;
begin
  for I := 0 to FNodes.Count - 1 do
    TRCNode(FNodes[I]).HeatInput := 0;
end;

{ Ein einzelner (kleiner) Teilschritt des expliziten, synchronen
  Euler-Verfahrens. Externe Wärmeeinträge (HeatInput) werden bei jedem
  Teilschritt erneut angerechnet, damit die Summe über alle Teilschritte
  DeltaTime * HeatInput ergibt. }
procedure TRCModel.StepOnce(DeltaTime: Double);
var
  I: Integer;
  LinkObj: TRCLink;
  A, B: TRCNode;
  Flow: Double;
  dQ: array of Double;
  IndexA, IndexB: Integer;
begin
  SetLength(dQ, FNodes.Count);

  { Alle Wärmeflüsse mit den *alten* Temperaturen berechnen }
  for I := 0 to FLinks.Count - 1 do
  begin
    LinkObj := TRCLink(FLinks[I]);

    A := LinkObj.NodeA;
    B := LinkObj.NodeB;

    if (A = nil) or (B = nil) or (LinkObj.Resistance <= 0) then
      Continue;

    Flow := (A.Temperature - B.Temperature) / LinkObj.Resistance;
    LinkObj.HeatFlow := Flow;

    IndexA := FNodes.IndexOf(A);
    IndexB := FNodes.IndexOf(B);

    if IndexA >= 0 then
      dQ[IndexA] := dQ[IndexA] - Flow;

    if IndexB >= 0 then
      dQ[IndexB] := dQ[IndexB] + Flow;
  end;

  { Externe Wärmeeinträge (Heizung, Sonne, ...) hinzufügen }
  for I := 0 to FNodes.Count - 1 do
    dQ[I] := dQ[I] + TRCNode(FNodes[I]).HeatInput;

  { Jetzt alle Temperaturen gleichzeitig fortschreiben }
  for I := 0 to FNodes.Count - 1 do
  begin
    if TRCNode(FNodes[I]).HeatCapacity > 0 then
      TRCNode(FNodes[I]).Temperature :=
        TRCNode(FNodes[I]).Temperature +
        dQ[I] * DeltaTime / TRCNode(FNodes[I]).HeatCapacity;
  end;
end;

procedure TRCModel.Step(DeltaTime: Double);
const
  { Konservative obere Schranke für einen einzelnen Teilschritt. Dünne,
    gut leitende Materialschichten (z. B. wenige mm Putz) haben ein sehr
    kleines Produkt aus Widerstand und Wärmekapazität; 20 s liegt sicher
    unterhalb der Stabilitätsgrenze für die in der Demo verwendeten
    Materialien und Bauteildicken. }
  MaxSubStepSeconds = 20.0;
var
  SubSteps, I: Integer;
  SubDeltaTime: Double;
begin
  if DeltaTime <= 0 then
    Exit;

  SubSteps := Trunc(DeltaTime / MaxSubStepSeconds) + 1;
  SubDeltaTime := DeltaTime / SubSteps;

  for I := 1 to SubSteps do
    StepOnce(SubDeltaTime);
end;

function TRCModel.NodeCount: Integer;
begin
  Result := FNodes.Count;
end;

function TRCModel.LinkCount: Integer;
begin
  Result := FLinks.Count;
end;

function TRCModel.Node(Index: Integer): TRCNode;
begin
  Result := TRCNode(FNodes[Index]);
end;

function TRCModel.Link(Index: Integer): TRCLink;
begin
  Result := TRCLink(FLinks[Index]);
end;

end.
