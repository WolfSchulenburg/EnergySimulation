{ ============================================================================
  uInsulationStandards.pas

  Grobe, nach Baualtersklasse/Dämmstandard gestaffelte Richtwerte für
  U-Werte und Luftwechselrate, wie sie für eine überschlägliche
  Wärmebilanz aus wenigen Eckdaten (Baujahr, "Altbau"/"Neubau"/...)
  gebraucht werden.

  WICHTIG: Das sind bewusst grobe, illustrative Anhaltswerte für ein
  Überschlagstool - keine verifizierten Norm- oder Bestandsdaten. Für eine
  belastbare energetische Bewertung (Energieausweis, Sanierungsplanung)
  müssen die tatsächlichen Bauteilaufbauten bzw. ein Vor-Ort-Aufmaß
  herangezogen werden. Wer genauere Werte hat, sollte sie in der
  Gebäudebeschreibung direkt als UWert_* angeben (siehe uBuildingDescription)
  - diese Tabelle greift nur, wo keine expliziten Werte vorliegen.
  ============================================================================ }
unit uInsulationStandards;

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TInsulationStandard = (
    isAltbauUnsaniert,   // vor ca. 1948, keine nennenswerte Dämmung
    isAltbau,            // ca. 1949-1978, vor der 1. Wärmeschutzverordnung
    isWSVO1977,          // ca. 1979-1994
    isWSVO1995,          // ca. 1995-2001
    isEnEV2002,          // ca. 2002-2008
    isEnEV2009,          // ca. 2009-2015
    isEnEV2016,          // ca. 2016-heute (bzw. GEG)
    isKfW55,             // Effizienzhaus-Niveau
    isPassivhaus         // Passivhausstandard
  );

  TInsulationValues = record
    UWall, URoof, UFloor, UWindow: Double; // W/(m²K)
    AirChangeRate: Double;                 // 1/h
  end;

{ Ordnet einen (deutschsprachigen) Namen einem Standard zu; erkennt u. a.
  "Altbau", "unsaniert", "Neubau", "EnEV2016", "KfW55", "Passivhaus" usw.
  Liefert False, wenn der Name nicht erkannt wurde (Result dann isEnEV2002
  als neutraler Mittelwert). }
function TryStandardFromName(const Name: string; out Standard: TInsulationStandard): Boolean;

{ Ordnet ein Baujahr grob einer Baualtersklasse zu. }
function StandardFromConstructionYear(Year: Integer): TInsulationStandard;

{ Liefert die Richtwerte für einen Standard. }
function GetInsulationValues(Standard: TInsulationStandard): TInsulationValues;

function StandardName(Standard: TInsulationStandard): string;

{ Grobe, in der Literatur häufig genannte Bandbreiten für den spezifischen
  Heizwärmebedarf (kWh/(m²a)) je Baualtersklasse - nur zum groben Abgleich
  ("liegt das Simulationsergebnis in der erwarteten Größenordnung?"), keine
  belastbare Referenz. }
procedure GetTypicalSpecificDemandRange(Standard: TInsulationStandard;
  out LowKWhPerM2a, HighKWhPerM2a: Double);

implementation

function TryStandardFromName(const Name: string; out Standard: TInsulationStandard): Boolean;
var
  N: string;
begin
  Result := True;
  N := LowerCase(Trim(Name));

  if (N = 'altbau_unsaniert') or (N = 'unsaniert') or (N = 'altbau unsaniert') then
    Standard := isAltbauUnsaniert
  else if (N = 'altbau') then
    Standard := isAltbau
  else if (N = 'wsvo1977') or (N = 'wschv1977') then
    Standard := isWSVO1977
  else if (N = 'wsvo1995') or (N = 'wschv1995') then
    Standard := isWSVO1995
  else if (N = 'enev2002') or (N = 'enev') then
    Standard := isEnEV2002
  else if (N = 'enev2009') then
    Standard := isEnEV2009
  else if (N = 'enev2016') or (N = 'geg') or (N = 'neubau') then
    Standard := isEnEV2016
  else if (N = 'kfw55') or (N = 'kfw70') or (N = 'effizienzhaus') then
    Standard := isKfW55
  else if (N = 'passivhaus') or (N = 'passivhausstandard') then
    Standard := isPassivhaus
  else
  begin
    Standard := isEnEV2002;
    Result := False;
  end;
end;

function StandardFromConstructionYear(Year: Integer): TInsulationStandard;
begin
  if Year <= 0 then
    Result := isAltbau            // unbekannt: neutrale, eher konservative Annahme
  else if Year < 1949 then
    Result := isAltbauUnsaniert
  else if Year < 1979 then
    Result := isAltbau
  else if Year < 1995 then
    Result := isWSVO1977
  else if Year < 2002 then
    Result := isWSVO1995
  else if Year < 2009 then
    Result := isEnEV2002
  else if Year < 2016 then
    Result := isEnEV2009
  else
    Result := isEnEV2016;
end;

function GetInsulationValues(Standard: TInsulationStandard): TInsulationValues;
begin
  { Alle Werte sind grobe, gerundete Anhaltswerte (W/(m²K) bzw. 1/h). }
  case Standard of
    isAltbauUnsaniert:
      begin Result.UWall := 1.40; Result.URoof := 1.00; Result.UFloor := 1.20; Result.UWindow := 2.80; Result.AirChangeRate := 1.00; end;
    isAltbau:
      begin Result.UWall := 1.20; Result.URoof := 0.80; Result.UFloor := 1.00; Result.UWindow := 2.70; Result.AirChangeRate := 0.80; end;
    isWSVO1977:
      begin Result.UWall := 0.90; Result.URoof := 0.50; Result.UFloor := 0.80; Result.UWindow := 2.70; Result.AirChangeRate := 0.60; end;
    isWSVO1995:
      begin Result.UWall := 0.50; Result.URoof := 0.30; Result.UFloor := 0.50; Result.UWindow := 1.80; Result.AirChangeRate := 0.50; end;
    isEnEV2002:
      begin Result.UWall := 0.35; Result.URoof := 0.25; Result.UFloor := 0.35; Result.UWindow := 1.50; Result.AirChangeRate := 0.50; end;
    isEnEV2009:
      begin Result.UWall := 0.28; Result.URoof := 0.20; Result.UFloor := 0.30; Result.UWindow := 1.30; Result.AirChangeRate := 0.45; end;
    isEnEV2016:
      begin Result.UWall := 0.24; Result.URoof := 0.18; Result.UFloor := 0.25; Result.UWindow := 1.10; Result.AirChangeRate := 0.40; end;
    isKfW55:
      begin Result.UWall := 0.18; Result.URoof := 0.14; Result.UFloor := 0.20; Result.UWindow := 0.90; Result.AirChangeRate := 0.35; end;
    isPassivhaus:
      begin Result.UWall := 0.12; Result.URoof := 0.10; Result.UFloor := 0.15; Result.UWindow := 0.80; Result.AirChangeRate := 0.30; end;
  else
    begin Result.UWall := 0.35; Result.URoof := 0.25; Result.UFloor := 0.35; Result.UWindow := 1.50; Result.AirChangeRate := 0.50; end;
  end;
end;

function StandardName(Standard: TInsulationStandard): string;
begin
  case Standard of
    isAltbauUnsaniert: Result := 'Altbau unsaniert (vor ca. 1948)';
    isAltbau:          Result := 'Altbau (ca. 1949-1978)';
    isWSVO1977:        Result := 'nach 1. Wärmeschutzverordnung (ca. 1979-1994)';
    isWSVO1995:        Result := 'nach WSVO 1995 (ca. 1995-2001)';
    isEnEV2002:        Result := 'EnEV 2002 (ca. 2002-2008)';
    isEnEV2009:        Result := 'EnEV 2009 (ca. 2009-2015)';
    isEnEV2016:        Result := 'EnEV 2016 / GEG (ab ca. 2016)';
    isKfW55:           Result := 'Effizienzhaus-Niveau (KfW 55/70)';
    isPassivhaus:      Result := 'Passivhausstandard';
  else
    Result := 'unbekannt';
  end;
end;

procedure GetTypicalSpecificDemandRange(Standard: TInsulationStandard;
  out LowKWhPerM2a, HighKWhPerM2a: Double);
begin
  case Standard of
    isAltbauUnsaniert: begin LowKWhPerM2a := 200; HighKWhPerM2a := 350; end;
    isAltbau:          begin LowKWhPerM2a := 150; HighKWhPerM2a := 220; end;
    isWSVO1977:        begin LowKWhPerM2a := 120; HighKWhPerM2a := 180; end;
    isWSVO1995:        begin LowKWhPerM2a := 80;  HighKWhPerM2a := 120; end;
    isEnEV2002:        begin LowKWhPerM2a := 60;  HighKWhPerM2a := 100; end;
    isEnEV2009:        begin LowKWhPerM2a := 50;  HighKWhPerM2a := 80;  end;
    isEnEV2016:        begin LowKWhPerM2a := 35;  HighKWhPerM2a := 65;  end;
    isKfW55:            begin LowKWhPerM2a := 25;  HighKWhPerM2a := 50;  end;
    isPassivhaus:       begin LowKWhPerM2a := 10;  HighKWhPerM2a := 20;  end;
  else
    begin LowKWhPerM2a := 60; HighKWhPerM2a := 100; end;
  end;
end;

end.
