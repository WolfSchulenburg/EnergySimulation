{ ============================================================================
  uWeather.pas

  Wetterzustand zu einem Zeitpunkt (Außentemperatur und Strahlungsgrößen).

  Zwei synthetische (nicht auf echten Messdaten beruhende) Wettermodelle:

    GenerateTestWeather   - das ursprüngliche, rein tageszeitabhängige
                             Modell aus dem Entwurfsgespräch (konstanter
                             Mittelwert, Sinuskurve über den Tag). Reicht
                             für eine Ein-Tages-Demo, aber nicht für eine
                             Jahresbetrachtung, da keine Jahreszeiten
                             abgebildet werden.

    GenerateWeather        - erweitert das Tagesmodell um einen Jahresgang
                             (TClimateProfile: Jahresmitteltemperatur,
                             Jahresamplitude, kältester Tag des Jahres) und
                             wird für die Jahres-Wärmebilanz (uHeatBalance)
                             gebraucht. Vereinfachung: die Tageslänge/das
                             Sonnenfenster wird ganzjährig gleich behandelt
                             (kein kürzerer Wintertag) - für eine grobe
                             Abschätzung ausreichend, für ein Auslegungstool
                             mit Anspruch auf Genauigkeit nicht.
  ============================================================================ }
unit uWeather;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, DateUtils, Math;

type

  TWeatherState = record
    OutsideTemperature: Double;          // °C

    DirectNormalIrradiance: Double;      // W/m², direkte Strahlung senkrecht zur Sonne
    DiffuseHorizontalIrradiance: Double; // W/m², diffuse Strahlung auf der Horizontalen
    GlobalHorizontalIrradiance: Double;  // W/m², Global­strahlung auf der Horizontalen

    WindSpeed: Double;                   // m/s
    RelativeHumidity: Double;            // %
  end;

  { TClimateProfile - grobe Kenngrößen eines Standortklimas, ausreichend für
    ein synthetisches Jahresmodell. Keine echten Klimadaten (DWD-Referenz-
    jahr o. ä.), sondern ein plausibler, glatter Jahresgang. }
  TClimateProfile = record
    AnnualMeanTemperature: Double; // °C, Jahresmitteltemperatur
    AnnualAmplitude: Double;       // °C, halber Abstand Sommer-/Wintermittel
    ColdestDayOfYear: Integer;     // Tag des Jahres (1..365) mit tiefster mittlerer Temperatur
    DailyAmplitude: Double;        // °C, Amplitude des Tagesgangs um den Tagesmittelwert
    PeakSolarIrradiance: Double;   // W/m², ungefähre sommerliche Spitzen-Direktstrahlung
  end;

{ Ein für Mitteleuropa/Deutschland plausibler Default (Jahresmittel ~9,5°C,
  kältester Tag Ende Januar). }
function DefaultClimateProfile: TClimateProfile;

{ Liefert ein einfaches, synthetisches Testwetter für einen gegebenen
  Zeitpunkt (nur Tagesgang, keine Jahreszeiten, keine realen Messdaten). }
function GenerateTestWeather(DateTime: TDateTime): TWeatherState;

{ Wie GenerateTestWeather, aber mit Jahresgang gemäß Climate - geeignet für
  Simulationen über mehrere Monate/ein Jahr. }
function GenerateWeather(DateTime: TDateTime;
  const Climate: TClimateProfile): TWeatherState;

implementation

function GenerateTestWeather(DateTime: TDateTime): TWeatherState;
var
  HourValue: Double;
  SolarFactor: Double;
begin
  HourValue := HourOf(DateTime) + MinuteOf(DateTime) / 60.0;

  { Temperatur: Minimum gegen 2 Uhr, Maximum gegen 14 Uhr }
  Result.OutsideTemperature :=
    19.0 + 6.0 * Sin(2.0 * Pi * (HourValue - 8.0) / 24.0);

  { Sonnenfaktor: 0 nachts, Maximum am Mittag, grob zwischen 5 und 20 Uhr }
  SolarFactor := Sin(Pi * (HourValue - 5.0) / 15.0);

  if SolarFactor < 0 then
    SolarFactor := 0;

  Result.DirectNormalIrradiance := 700.0 * SolarFactor;
  Result.DiffuseHorizontalIrradiance := 120.0 * SolarFactor;
  Result.GlobalHorizontalIrradiance := 500.0 * SolarFactor;

  Result.WindSpeed := 3.0;
  Result.RelativeHumidity := 60.0;
end;

function DefaultClimateProfile: TClimateProfile;
begin
  Result.AnnualMeanTemperature := 9.5;
  Result.AnnualAmplitude := 9.5;    // -> ca. 0°C im Winter, ca. 19°C im Sommer
  Result.ColdestDayOfYear := 20;    // ca. 20. Januar
  Result.DailyAmplitude := 6.0;
  Result.PeakSolarIrradiance := 700.0;
end;

function GenerateWeather(DateTime: TDateTime;
  const Climate: TClimateProfile): TWeatherState;
var
  HourValue: Double;
  DayOfYear: Integer;
  SeasonalPhase: Double;
  SeasonalTemperature: Double;
  SeasonalSolarFactor: Double;
  DailySolarFactor: Double;
begin
  HourValue := HourOf(DateTime) + MinuteOf(DateTime) / 60.0;
  DayOfYear := DayOfTheYear(DateTime);

  { Phase des Jahresgangs: 0 am kältesten Tag, Pi (Sommer) ein halbes Jahr
    später, 2*Pi wieder am kältesten Tag. }
  SeasonalPhase := 2.0 * Pi * (DayOfYear - Climate.ColdestDayOfYear) / 365.0;

  { Jahresmittelwert der Temperatur an diesem Tag: Minimum am kältesten Tag,
    Maximum ein halbes Jahr später. }
  SeasonalTemperature := Climate.AnnualMeanTemperature -
    Climate.AnnualAmplitude * Cos(SeasonalPhase);

  { Tagesgang um den Jahresmittelwert dieses Tages, gleiche Form wie in
    GenerateTestWeather (Minimum gegen 2 Uhr, Maximum gegen 14 Uhr). }
  Result.OutsideTemperature := SeasonalTemperature +
    Climate.DailyAmplitude * Sin(2.0 * Pi * (HourValue - 8.0) / 24.0);

  { Saisonaler Strahlungsfaktor, in Phase mit der Temperatur (0,25 im
    Winterminimum, 1,0 im Sommermaximum) - eine grobe, aber plausible
    Näherung ohne echte Tageslängen-/Sonnenstandsberechnung. }
  SeasonalSolarFactor := 0.25 + 0.75 * (0.5 - 0.5 * Cos(SeasonalPhase + Pi));

  { Tagesgang der Einstrahlung, gleiche Form wie in GenerateTestWeather. }
  DailySolarFactor := Sin(Pi * (HourValue - 5.0) / 15.0);
  if DailySolarFactor < 0 then
    DailySolarFactor := 0;

  Result.DirectNormalIrradiance :=
    Climate.PeakSolarIrradiance * SeasonalSolarFactor * DailySolarFactor;

  Result.DiffuseHorizontalIrradiance :=
    (120.0 / 700.0) * Climate.PeakSolarIrradiance * SeasonalSolarFactor * DailySolarFactor;

  Result.GlobalHorizontalIrradiance :=
    (500.0 / 700.0) * Climate.PeakSolarIrradiance * SeasonalSolarFactor * DailySolarFactor;

  Result.WindSpeed := 3.0;
  Result.RelativeHumidity := 60.0;
end;

end.
