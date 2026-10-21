{ ============================================================================
  uSimulation.pas

  Die eigentliche Simulationsschleife: verbindet Gebäude, RC-Modell,
  Wettermodell, Sonnenmodell und einen einfachen Zweipunkt-Heizungsregler
  zu einem Objekt, dessen Step(DateTime)-Methode einen Zeitschritt (per
  Default 5 Minuten) simuliert.

  Ablauf pro Schritt (wie im Gespräch als "Uhrzeit -> Wetter/Sonne ->
  Wärmequellen -> RC-Modell -> neue Temperaturen" skizziert):
    1. Wärmeeinträge aller Knoten zurücksetzen
    2. Wetter für den Zeitpunkt bestimmen, Außenluftknoten setzen - wahl-
       weise synthetisches Tages- (GenerateTestWeather) oder Jahresmodell
       (GenerateWeather) oder, wenn UseTRYData gesetzt ist, echte
       DWD-TRY-Stundenwerte (siehe uTRYImport.pas)
    3. Solare Gewinne durch alle transparenten Flächen berechnen und dem
       jeweiligen Raum zuschlagen
    4. Heizungsregler anwenden
    5. RC-Netz einen Zeitschritt integrieren
  ============================================================================ }
unit uSimulation;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  uBuilding,
  uRCModel,
  uSolar,
  uWeather,
  uTRYImport;

type

  { TRCHeatingController
    Ein einfacher Zweipunktregler (Hysterese) mit maximaler Heizleistung,
    der einem einzelnen Knoten (typischerweise dem beheizten Raum) Wärme
    zuführt, solange dessen Temperatur unter Sollwert minus halbe
    Hysterese liegt, und abschaltet, sobald sie Sollwert plus halbe
    Hysterese erreicht. }
  TRCHeatingController = class
  private
    FNode: TRCNode;

    FSetpoint: Double;
    FDeadBand: Double;
    FMaxPower: Double;

    FHeatingOn: Boolean;
  public
    constructor Create(Node: TRCNode);

    procedure Apply(Model: TRCModel);

    property Setpoint: Double read FSetpoint write FSetpoint;
    property DeadBand: Double read FDeadBand write FDeadBand;
    property MaxPower: Double read FMaxPower write FMaxPower;
    property HeatingOn: Boolean read FHeatingOn;
  end;


  { TRCSimulation
    Fasst Gebäude, RC-Modell, Sonnenmodell und Heizungsregler zu einer
    laufbereiten Simulation zusammen. }
  TRCSimulation = class
  private
    FBuilding: TBuilding;
    FModel: TRCModel;
    FSolar: TSolarModel;
    FHeating: TRCHeatingController;

    FOutsideTemperature: Double;
    FTimeStepSeconds: Double;
    FLastWeather: TWeatherState;

    FUseSeasonalClimate: Boolean;
    FClimate: TClimateProfile;

    FUseTRYData: Boolean;
    FTRYYear: TTRYYear;

    FTotalHeatingEnergy: Double; // J, seit Create bzw. ResetEnergyTotals()
  public
    { HeatedRoomID benennt den Raum (TRoom.ID), an dem der Heizungsregler
      angreift - im Demo-Gebäude ist das 'living'. }
    constructor Create(Building: TBuilding; Model: TRCModel;
      const HeatedRoomID: string = 'living');
    destructor Destroy; override;

    { Simuliert einen Zeitschritt für den gegebenen Zeitpunkt (Datum+Uhrzeit
      bestimmen sowohl das Wetter als auch den Sonnenstand). Verwendet
      standardmäßig das tageszeitabhängige Testwetter (GenerateTestWeather);
      ist UseSeasonalClimate gesetzt, wird stattdessen GenerateWeather mit
      dem Climate-Profil verwendet (nötig für Simulationen über mehrere
      Monate/ein Jahr, siehe uHeatBalance.pas). }
    procedure Step(DateTime: TDateTime);

    procedure ResetEnergyTotals;

    property Heating: TRCHeatingController read FHeating;
    property Solar: TSolarModel read FSolar;
    property OutsideTemperature: Double read FOutsideTemperature;
    property LastWeather: TWeatherState read FLastWeather;
    property TimeStepSeconds: Double read FTimeStepSeconds write FTimeStepSeconds;

    property UseSeasonalClimate: Boolean read FUseSeasonalClimate write FUseSeasonalClimate;
    property Climate: TClimateProfile read FClimate write FClimate;

    { UseTRYData hat Vorrang vor UseSeasonalClimate: ist es gesetzt, kommt
      Temperatur/Strahlung für jeden Zeitschritt aus TRYYear (echte
      DWD-Stundenwerte, siehe uTRYImport.pas) statt aus einem synthetischen
      Modell. Fehlende Stunden in TRYYear (Filled = False) liefern 0 -
      LoadTRYYear() sollte dafür vorher geprüft/gewarnt haben. }
    property UseTRYData: Boolean read FUseTRYData write FUseTRYData;
    property TRYYear: TTRYYear read FTRYYear write FTRYYear;

    { Aufsummierte, tatsächlich vom Heizungsregler eingebrachte Wärmemenge
      seit Create()/ResetEnergyTotals(), in Joule bzw. kWh. }
    property TotalHeatingEnergy: Double read FTotalHeatingEnergy;
    function TotalHeatingEnergyKWh: Double;
  end;

implementation

{ TRCHeatingController }

constructor TRCHeatingController.Create(Node: TRCNode);
begin
  inherited Create;

  FNode := Node;

  FSetpoint := 21.0;
  FDeadBand := 0.5;
  FMaxPower := 5000.0;

  FHeatingOn := False;
end;

procedure TRCHeatingController.Apply(Model: TRCModel);
begin
  if FNode = nil then
    Exit;

  if FNode.Temperature < FSetpoint - FDeadBand then
    FHeatingOn := True
  else if FNode.Temperature > FSetpoint + FDeadBand then
    FHeatingOn := False;

  if FHeatingOn then
    FNode.HeatInput := FNode.HeatInput + FMaxPower
  else
    FNode.HeatInput := FNode.HeatInput + 0.0;
end;

{ TRCSimulation }

constructor TRCSimulation.Create(Building: TBuilding; Model: TRCModel;
  const HeatedRoomID: string);
var
  HeatedNode: TRCNode;
begin
  inherited Create;

  FBuilding := Building;
  FModel := Model;
  FSolar := TSolarModel.Create;

  FOutsideTemperature := 0.0;
  FTimeStepSeconds := 300.0;

  FUseSeasonalClimate := False;
  FClimate := DefaultClimateProfile;

  FUseTRYData := False;

  FTotalHeatingEnergy := 0.0;

  HeatedNode := FModel.FindNode('room_' + HeatedRoomID);

  FHeating := TRCHeatingController.Create(HeatedNode);
end;

destructor TRCSimulation.Destroy;
begin
  FHeating.Free;
  FSolar.Free;

  inherited Destroy;
end;

procedure TRCSimulation.ResetEnergyTotals;
begin
  FTotalHeatingEnergy := 0.0;
end;

function TRCSimulation.TotalHeatingEnergyKWh: Double;
begin
  Result := FTotalHeatingEnergy / 3600000.0;
end;

procedure TRCSimulation.Step(DateTime: TDateTime);
var
  OutsideNode: TRCNode;
  I: Integer;
  Surface: TSurface;
  Gain: Double;
  RoomNode: TRCNode;
  TRYRec: TTRYRecord;
  Sun: TSunPosition;
begin
  FModel.ClearHeatInputs;

  { Wetter für diesen Zeitpunkt }
  if FUseTRYData then
  begin
    TRYRec := GetTRYRecord(FTRYYear, HourIndexOfYear(DateTime));

    FLastWeather.OutsideTemperature := TRYRec.Temperature;
    FLastWeather.WindSpeed := TRYRec.WindSpeed;
    FLastWeather.RelativeHumidity := TRYRec.RelHumidity;

    FLastWeather.DiffuseHorizontalIrradiance := TRYRec.DiffuseSunPowerHorizontal;
    FLastWeather.GlobalHorizontalIrradiance :=
      TRYRec.DirectSunPowerHorizontal + TRYRec.DiffuseSunPowerHorizontal;

    { uSolar.pas (SolarIrradianceOnSurface) erwartet die Direktnormal-
      strahlung (senkrecht zur Sonne), TRY liefert B jedoch als
      Direktstrahlung auf der Horizontalen. Umrechnung über den ohnehin
      für die Fenster-Einstrahlung benötigten Sonnenstand:
      DNI = B_horizontal / sin(Sonnenhöhe). Unterhalb von 3° Sonnenhöhe
      (Dämmerung, streifender Einfall) wird 0 angenommen, um eine Division
      durch (nahe) Null und dadurch unrealistische Spitzenwerte zu
      vermeiden - ein in der Praxis übliches, einfaches Vorgehen. }
    Sun := CalculateSunPosition(DateTime, FSolar.Latitude, FSolar.Longitude, FSolar.TimeZone);
    if Sun.IsAboveHorizon and (Sun.Elevation > 3.0) then
      FLastWeather.DirectNormalIrradiance :=
        TRYRec.DirectSunPowerHorizontal / Sin(DegToRad(Sun.Elevation))
    else
      FLastWeather.DirectNormalIrradiance := 0.0;
  end
  else if FUseSeasonalClimate then
    FLastWeather := GenerateWeather(DateTime, FClimate)
  else
    FLastWeather := GenerateTestWeather(DateTime);

  FOutsideTemperature := FLastWeather.OutsideTemperature;

  OutsideNode := FModel.FindNode('outside');
  if OutsideNode <> nil then
    OutsideNode.Temperature := FOutsideTemperature;

  { Solare Gewinne: jede transparente Fläche speist ihren Gewinn in den
    Raum ein, an den ihre SideA grenzt. }
  for I := 0 to FBuilding.Surfaces.Count - 1 do
  begin
    Surface := TSurface(FBuilding.Surfaces[I]);

    if not Surface.IsTransparent then
      Continue;

    Gain := FSolar.CalculateGain(Surface, DateTime,
      FLastWeather.DirectNormalIrradiance,
      FLastWeather.DiffuseHorizontalIrradiance,
      FLastWeather.GlobalHorizontalIrradiance);

    if (Surface.SideA <> nil) and (Surface.SideA.Space <> nil) then
    begin
      RoomNode := FModel.FindNode('room_' + Surface.SideA.Space.ID);

      if RoomNode <> nil then
        RoomNode.HeatInput := RoomNode.HeatInput + Gain;
    end;
  end;

  { Heizung }
  FHeating.Apply(FModel);

  if FHeating.HeatingOn then
    FTotalHeatingEnergy := FTotalHeatingEnergy + FHeating.MaxPower * FTimeStepSeconds;

  { RC-System integrieren }
  FModel.Step(FTimeStepSeconds);
end;

end.
