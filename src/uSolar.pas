{ ============================================================================
  uSolar.pas

  Sonnenstand (Azimut/Höhe) aus Datum, Uhrzeit und Standort, sowie die
  solare Einstrahlung auf eine beliebig ausgerichtete Fläche und der daraus
  resultierende solare Wärmeeintrag durch ein Fenster.

  Die Einstrahlung setzt sich - wie im Gespräch entwickelt - aus drei
  Anteilen zusammen:
    - direkter Strahlung (abhängig vom Einfallswinkel der Sonne),
    - diffuser Himmelsstrahlung (angenähert über die Flächenneigung),
    - vom Erdboden reflektierter Strahlung (Albedo).
  ============================================================================ }
unit uSolar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, Math,
  uBuilding,
  uRCModel;

type

  TSunPosition = record
    Azimuth: Double;         // Grad, 0=N, 90=O, 180=S, 270=W
    Elevation: Double;       // Grad über dem Horizont
    Zenith: Double;          // Grad vom Zenit
    IsAboveHorizon: Boolean;
  end;

{ Sonnenstand nach einem vereinfachten astronomischen Standardverfahren
  (Spencer-Näherung für Deklination/Zeitgleichung). }
function CalculateSunPosition(const ADateTime: TDateTime;
  Latitude, Longitude, TimeZone: Double): TSunPosition;

{ Direkte Einstrahlung (W/m²) auf eine Fläche gegebener Ausrichtung/Neigung,
  aus der Direktnormalstrahlung (senkrecht zur Sonne gemessen). }
function SolarIrradianceOnSurface(const Sun: TSunPosition;
  SurfaceAzimuth, SurfaceTilt, DirectNormalIrradiance: Double): Double;

{ Diffuse Himmelsstrahlung auf eine geneigte Fläche, isotropes Modell. }
function DiffuseIrradianceOnSurface(SurfaceTilt,
  DiffuseHorizontalIrradiance: Double): Double;

{ Vom Erdboden reflektierte Strahlung auf eine geneigte Fläche. }
function GroundReflectedIrradiance(SurfaceTilt, GlobalHorizontalIrradiance,
  GroundAlbedo: Double): Double;

{ Solarer Wärmeeintrag (W) durch ein Fenster: Summe aus direkter, diffuser
  und bodenreflektierter Einstrahlung, multipliziert mit Fläche, g-Wert und
  Verschattungsfaktor. }
function SolarGainThroughWindow(const Sun: TSunPosition;
  WindowAzimuth, WindowTilt, Area, SolarGValue, ShadingFactor,
  DirectNormalIrradiance, DiffuseHorizontalIrradiance,
  GlobalHorizontalIrradiance, GroundAlbedo: Double): Double;


type

  { TSolarModel - fasst Standort und die Berechnung des solaren Gewinns für
    eine einzelne Fläche zu einem einfach zu benutzenden Objekt zusammen. }
  TSolarModel = class
  private
    FLatitude: Double;
    FLongitude: Double;
    FTimeZone: Double;
    FGroundAlbedo: Double;
  public
    constructor Create;

    function CalculateGain(Surface: TSurface; DateTime: TDateTime;
      DirectNormalIrradiance, DiffuseHorizontalIrradiance,
      GlobalHorizontalIrradiance: Double): Double;

    property Latitude: Double read FLatitude write FLatitude;
    property Longitude: Double read FLongitude write FLongitude;
    property TimeZone: Double read FTimeZone write FTimeZone;
    property GroundAlbedo: Double read FGroundAlbedo write FGroundAlbedo;
  end;

implementation

function NormalizeAngle(A: Double): Double;
begin
  Result := A;

  while Result < 0 do
    Result := Result + 360.0;

  while Result >= 360.0 do
    Result := Result - 360.0;
end;

function CalculateSunPosition(const ADateTime: TDateTime;
  Latitude, Longitude, TimeZone: Double): TSunPosition;
var
  HourValue: Double;
  N: Integer;
  Gamma: Double;
  Declination, EquationOfTime: Double;
  SolarTime, HourAngle: Double;
  LatRad, DeclRad, HRad: Double;
  Elevation, Azimuth: Double;
begin
  HourValue := HourOf(ADateTime) + MinuteOf(ADateTime) / 60.0 +
    SecondOf(ADateTime) / 3600.0;

  { Tag des Jahres }
  N := DayOfTheYear(ADateTime);

  { Winkel für die Jahreszeit }
  Gamma := 2.0 * Pi / 365.0 * (N - 1 + (HourValue - 12.0) / 24.0);

  { Sonnendeklination (Spencer-Näherung) }
  Declination :=
    0.006918
    - 0.399912 * Cos(Gamma)
    + 0.070257 * Sin(Gamma)
    - 0.006758 * Cos(2 * Gamma)
    + 0.000907 * Sin(2 * Gamma)
    - 0.002697 * Cos(3 * Gamma)
    + 0.001480 * Sin(3 * Gamma);

  { Zeitgleichung in Minuten }
  EquationOfTime :=
    229.18 *
    (0.000075
     + 0.001868 * Cos(Gamma)
     - 0.032077 * Sin(Gamma)
     - 0.014615 * Cos(2 * Gamma)
     - 0.040849 * Sin(2 * Gamma));

  { Wahre Sonnenzeit }
  SolarTime := HourValue +
    (4.0 * (Longitude - TimeZone * 15.0) + EquationOfTime) / 60.0;

  { Stundenwinkel }
  HourAngle := 15.0 * (SolarTime - 12.0);

  LatRad := DegToRad(Latitude);
  DeclRad := Declination;
  HRad := DegToRad(HourAngle);

  { Sonnenhöhe }
  Elevation := ArcSin(
    Sin(LatRad) * Sin(DeclRad) +
    Cos(LatRad) * Cos(DeclRad) * Cos(HRad));

  Result.Elevation := RadToDeg(Elevation);
  Result.Zenith := 90.0 - Result.Elevation;

  { Sonnenazimut }
  Azimuth := ArcTan2(
    Sin(HRad),
    Cos(HRad) * Sin(LatRad) - Tan(DeclRad) * Cos(LatRad));

  { Umrechnung auf: 0°=Nord, 90°=Ost, 180°=Süd, 270°=West }
  Result.Azimuth := NormalizeAngle(RadToDeg(Azimuth) + 180.0);

  Result.IsAboveHorizon := Result.Elevation > 0.0;
end;

function SolarIrradianceOnSurface(const Sun: TSunPosition;
  SurfaceAzimuth, SurfaceTilt, DirectNormalIrradiance: Double): Double;
var
  SunAz, SunEl, SurfaceAz, SurfaceTiltRad: Double;
  CosIncidence: Double;
begin
  if not Sun.IsAboveHorizon then
  begin
    Result := 0;
    Exit;
  end;

  SunAz := DegToRad(Sun.Azimuth);
  SunEl := DegToRad(Sun.Elevation);

  SurfaceAz := DegToRad(SurfaceAzimuth);
  SurfaceTiltRad := DegToRad(SurfaceTilt);

  CosIncidence :=
    Sin(SunEl) * Cos(SurfaceTiltRad)
    +
    Cos(SunEl) * Sin(SurfaceTiltRad) * Cos(SunAz - SurfaceAz);

  if CosIncidence <= 0 then
  begin
    Result := 0;
    Exit;
  end;

  Result := DirectNormalIrradiance * CosIncidence;
end;

function DiffuseIrradianceOnSurface(SurfaceTilt,
  DiffuseHorizontalIrradiance: Double): Double;
begin
  if DiffuseHorizontalIrradiance <= 0 then
  begin
    Result := 0;
    Exit;
  end;

  { Isotropes Himmelsmodell: eine senkrechte Fläche "sieht" die Hälfte des
    Himmels, eine horizontale Fläche den ganzen Himmel. }
  Result := DiffuseHorizontalIrradiance *
    (1.0 + Cos(DegToRad(SurfaceTilt))) / 2.0;
end;

function GroundReflectedIrradiance(SurfaceTilt, GlobalHorizontalIrradiance,
  GroundAlbedo: Double): Double;
begin
  Result := GlobalHorizontalIrradiance * GroundAlbedo *
    (1.0 - Cos(DegToRad(SurfaceTilt))) / 2.0;
end;

function SolarGainThroughWindow(const Sun: TSunPosition;
  WindowAzimuth, WindowTilt, Area, SolarGValue, ShadingFactor,
  DirectNormalIrradiance, DiffuseHorizontalIrradiance,
  GlobalHorizontalIrradiance, GroundAlbedo: Double): Double;
var
  DirectPart, DiffusePart, GroundPart, TotalIrradiance: Double;
begin
  if not Sun.IsAboveHorizon then
    DirectPart := 0
  else
    DirectPart := SolarIrradianceOnSurface(Sun, WindowAzimuth, WindowTilt,
      DirectNormalIrradiance);

  DiffusePart := DiffuseIrradianceOnSurface(WindowTilt,
    DiffuseHorizontalIrradiance);

  GroundPart := GroundReflectedIrradiance(WindowTilt,
    GlobalHorizontalIrradiance, GroundAlbedo);

  TotalIrradiance := DirectPart + DiffusePart + GroundPart;

  Result := TotalIrradiance * Area * SolarGValue * ShadingFactor;
end;

{ TSolarModel }

constructor TSolarModel.Create;
begin
  inherited Create;

  { Standardwerte: Hamburg }
  FLatitude := 53.43;
  FLongitude := 10.37;
  FTimeZone := 1.0;
  FGroundAlbedo := 0.20;
end;

function TSolarModel.CalculateGain(Surface: TSurface; DateTime: TDateTime;
  DirectNormalIrradiance, DiffuseHorizontalIrradiance,
  GlobalHorizontalIrradiance: Double): Double;
var
  Sun: TSunPosition;
begin
  Result := 0;

  if Surface = nil then
    Exit;

  if not Surface.IsTransparent then
    Exit;

  if Surface.Area <= 0 then
    Exit;

  Sun := CalculateSunPosition(DateTime, FLatitude, FLongitude, FTimeZone);

  Result := SolarGainThroughWindow(Sun, Surface.Orientation, Surface.Tilt,
    Surface.Area, Surface.SolarGValue, Surface.ShadingFactor,
    DirectNormalIrradiance, DiffuseHorizontalIrradiance,
    GlobalHorizontalIrradiance, FGroundAlbedo);
end;

end.
