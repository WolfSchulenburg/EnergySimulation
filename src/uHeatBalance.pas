{ ============================================================================
  uHeatBalance.pas

  Überschlägliche (stationäre) Auslegungsheizlast aus einem TRCModel: die
  Summe aller Leitwerte (1/R) direkt zwischen dem Raumknoten und den festen
  Randknoten (Außenluft, Erdreich), multipliziert mit der jeweiligen
  Temperaturdifferenz - das ist die klassische "Kurzverfahren"-Vorstellung
  einer Heizlastberechnung (vgl. DIN EN 12831, vereinfacht): Transmission
  + Lüftung bei einer winterlichen Auslegungsaußentemperatur.

  WICHTIG - Geltungsbereich: Diese Funktion setzt voraus, dass der Raum
  direkt (ohne Zwischenknoten) mit Außenluft/Erdreich verbunden ist, wie es
  uBuildingGenerator erzeugt (dort werden Bauteile nur über einen
  U-Wert-Widerstand ohne Materialschichten modelliert). Für ein Netz mit
  mehrschichtigen Bauteilen (Zwischenknoten je Materialschicht, wie im
  Demo-Gebäude mit TConstruction) unterschätzt diese Summe die tatsächliche
  Heizlast, weil solche Ketten hier nicht aufgelöst werden - für die
  generierten Gebäude aus uBuildingGenerator ist sie exakt.
  ============================================================================ }
unit uHeatBalance;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  uRCModel;

type
  TDesignHeatLoadResult = record
    TransmissionConductanceOutside: Double; // W/K, Wände/Fenster/Dach -> Außenluft
    TransmissionConductanceGround: Double;  // W/K, Bodenplatte -> Erdreich
    VentilationConductance: Double;         // W/K

    TransmissionLossOutside: Double; // W
    TransmissionLossGround: Double;  // W
    VentilationLoss: Double;         // W

    TotalHeatLoad: Double;           // W
  end;

function EstimateDesignHeatLoad(Model: TRCModel; const RoomNodeID: string;
  IndoorTemp, OutdoorDesignTemp, GroundTemperature: Double): TDesignHeatLoadResult;

{ kWh/a durch die (beheizte) Fläche = übliche Kennzahl "spezifischer
  Heizwärmebedarf". UsableFloorArea in m² (typischerweise Grundfläche *
  Stockwerke). }
function SpecificHeatingDemand(AnnualHeatingKWh, UsableFloorArea: Double): Double;

implementation

function EstimateDesignHeatLoad(Model: TRCModel; const RoomNodeID: string;
  IndoorTemp, OutdoorDesignTemp, GroundTemperature: Double): TDesignHeatLoadResult;
var
  I: Integer;
  L: TRCLink;
  RoomNode, OutsideNode, GroundNode, OtherNode: TRCNode;
begin
  FillChar(Result, SizeOf(Result), 0);

  RoomNode := Model.FindNode(RoomNodeID);
  if RoomNode = nil then
    Exit;

  OutsideNode := Model.FindNode('outside');
  GroundNode := Model.FindNode('ground');

  for I := 0 to Model.LinkCount - 1 do
  begin
    L := Model.Link(I);

    if L.Resistance <= 0 then
      Continue;

    if L.NodeA = RoomNode then
      OtherNode := L.NodeB
    else if L.NodeB = RoomNode then
      OtherNode := L.NodeA
    else
      Continue; // Link berührt den Raumknoten nicht direkt (z. B. Speichermasse)

    if (OtherNode = OutsideNode) and (OutsideNode <> nil) then
    begin
      if L.Kind = lkVentilation then
        Result.VentilationConductance := Result.VentilationConductance + 1.0 / L.Resistance
      else
        Result.TransmissionConductanceOutside := Result.TransmissionConductanceOutside + 1.0 / L.Resistance;
    end
    else if (OtherNode = GroundNode) and (GroundNode <> nil) then
      Result.TransmissionConductanceGround := Result.TransmissionConductanceGround + 1.0 / L.Resistance;
  end;

  Result.TransmissionLossOutside := Result.TransmissionConductanceOutside * (IndoorTemp - OutdoorDesignTemp);
  Result.VentilationLoss := Result.VentilationConductance * (IndoorTemp - OutdoorDesignTemp);
  Result.TransmissionLossGround := Result.TransmissionConductanceGround * (IndoorTemp - GroundTemperature);

  Result.TotalHeatLoad :=
    Result.TransmissionLossOutside + Result.VentilationLoss + Result.TransmissionLossGround;
end;

function SpecificHeatingDemand(AnnualHeatingKWh, UsableFloorArea: Double): Double;
begin
  if UsableFloorArea > 0 then
    Result := AnnualHeatingKWh / UsableFloorArea
  else
    Result := 0;
end;

end.
