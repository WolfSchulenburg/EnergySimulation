{ ============================================================================
  uGeometry.pas

  Geometrische Grundlagen der Gebäudesimulation: 3D-Punkte, Vektor-Operationen
  und ein einfaches (ebenes) Polygon, das Flächeninhalt, Flächennormale,
  Ausrichtung (Azimut) und Neigung (Tilt) aus seinen Eckpunkten berechnet.

  Diese Unit fasst die im Entwurfsgespräch entwickelte "echte Geometrie"
  zusammen (Abschnitt "TPolygon bekommt echte Geometrie"): statt Fläche,
  Orientierung und Neigung von Hand zu setzen, werden sie aus den 3D-Punkten
  hergeleitet.

  Koordinatensystem (wie im Gespräch festgelegt):
    X = Osten, Y = Norden, Z = oben
    Azimut: 0° = Norden, 90° = Osten, 180° = Süden, 270° = Westen
    Tilt:   0° = horizontal (Dach), 90° = senkrecht (Wand), 180° = nach unten
  ============================================================================ }
unit uGeometry;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

type

  TPoint3D = record
    X: Double;
    Y: Double;
    Z: Double;
  end;

function Point3D(X, Y, Z: Double): TPoint3D;

{ Vektor-Hilfsfunktionen }
function VectorAdd(const A, B: TPoint3D): TPoint3D;
function VectorSubtract(const A, B: TPoint3D): TPoint3D;
function VectorScale(const A: TPoint3D; S: Double): TPoint3D;
function CrossProduct(const A, B: TPoint3D): TPoint3D;
function DotProduct(const A, B: TPoint3D): Double;
function VectorLength(const A: TPoint3D): Double;
function NormalizeVector(const A: TPoint3D): TPoint3D;

type

  { TPolygon
    Ein ebenes Polygon aus 3D-Punkten (z. B. die vier Eckpunkte einer Wand
    oder eines Fensters). Fläche und Normale werden mit der verallgemeinerten
    Kreuzprodukt-Formel für beliebige (auch nicht-achsparallele) 3D-Polygone
    berechnet, so dass auch gedrehte Gebäude korrekt erfasst werden. }
  TPolygon = class
  private
    FPoints: array of TPoint3D;
  public
    procedure AddPoint(const P: TPoint3D);
    procedure Clear;
    function Count: Integer;
    function Point(Index: Integer): TPoint3D;

    { Flächeninhalt in m² }
    function Area: Double;

    { Normalisierte Flächennormale }
    function Normal: TPoint3D;

    { Schwerpunkt der Eckpunkte }
    function Centroid: TPoint3D;

    { Ausrichtung in Grad (0=N, 90=O, 180=S, 270=W), aus der Normale }
    function Azimuth: Double;

    { Neigung in Grad (0=horizontal, 90=senkrecht), aus der Normale }
    function Tilt: Double;
  end;

implementation

function Point3D(X, Y, Z: Double): TPoint3D;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
end;

function VectorAdd(const A, B: TPoint3D): TPoint3D;
begin
  Result.X := A.X + B.X;
  Result.Y := A.Y + B.Y;
  Result.Z := A.Z + B.Z;
end;

function VectorSubtract(const A, B: TPoint3D): TPoint3D;
begin
  Result.X := A.X - B.X;
  Result.Y := A.Y - B.Y;
  Result.Z := A.Z - B.Z;
end;

function VectorScale(const A: TPoint3D; S: Double): TPoint3D;
begin
  Result.X := A.X * S;
  Result.Y := A.Y * S;
  Result.Z := A.Z * S;
end;

function CrossProduct(const A, B: TPoint3D): TPoint3D;
begin
  Result.X := A.Y * B.Z - A.Z * B.Y;
  Result.Y := A.Z * B.X - A.X * B.Z;
  Result.Z := A.X * B.Y - A.Y * B.X;
end;

function DotProduct(const A, B: TPoint3D): Double;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function VectorLength(const A: TPoint3D): Double;
begin
  Result := Sqrt(A.X * A.X + A.Y * A.Y + A.Z * A.Z);
end;

function NormalizeVector(const A: TPoint3D): TPoint3D;
var
  L: Double;
begin
  L := VectorLength(A);
  if L <= 0 then
  begin
    Result.X := 0;
    Result.Y := 0;
    Result.Z := 0;
    Exit;
  end;
  Result := VectorScale(A, 1.0 / L);
end;

{ TPolygon }

procedure TPolygon.AddPoint(const P: TPoint3D);
var
  N: Integer;
begin
  N := Length(FPoints);
  SetLength(FPoints, N + 1);
  FPoints[N] := P;
end;

procedure TPolygon.Clear;
begin
  SetLength(FPoints, 0);
end;

function TPolygon.Count: Integer;
begin
  Result := Length(FPoints);
end;

function TPolygon.Point(Index: Integer): TPoint3D;
begin
  Result := FPoints[Index];
end;

{ Flächeninhalt eines beliebigen (ebenen, evtl. nicht-konvexen) 3D-Polygons
  über eine Dreiecksfächerung vom ersten Punkt aus:
    A = 1/2 * Summe_i (P(i) - P0) Kreuzprodukt (P(i+1) - P0), Betrag der Summe }
function TPolygon.Area: Double;
var
  I: Integer;
  P0, P1: TPoint3D;
  Sum: TPoint3D;
begin
  Result := 0;
  if Count < 3 then
    Exit;

  Sum.X := 0;
  Sum.Y := 0;
  Sum.Z := 0;

  P0 := FPoints[0];

  for I := 1 to Count - 2 do
  begin
    P1 := FPoints[I];
    Sum := VectorAdd(Sum,
      CrossProduct(
        VectorSubtract(P1, P0),
        VectorSubtract(FPoints[I + 1], P0)));
  end;

  Result := 0.5 * VectorLength(Sum);
end;

function TPolygon.Normal: TPoint3D;
var
  I: Integer;
  P0: TPoint3D;
  Sum: TPoint3D;
begin
  Result.X := 0;
  Result.Y := 0;
  Result.Z := 0;

  if Count < 3 then
    Exit;

  P0 := FPoints[0];

  Sum.X := 0;
  Sum.Y := 0;
  Sum.Z := 0;

  for I := 1 to Count - 2 do
  begin
    Sum := VectorAdd(Sum,
      CrossProduct(
        VectorSubtract(FPoints[I], P0),
        VectorSubtract(FPoints[I + 1], P0)));
  end;

  Result := NormalizeVector(Sum);
end;

function TPolygon.Centroid: TPoint3D;
var
  I: Integer;
begin
  Result.X := 0;
  Result.Y := 0;
  Result.Z := 0;

  if Count = 0 then
    Exit;

  for I := 0 to Count - 1 do
  begin
    Result.X := Result.X + FPoints[I].X;
    Result.Y := Result.Y + FPoints[I].Y;
    Result.Z := Result.Z + FPoints[I].Z;
  end;

  Result.X := Result.X / Count;
  Result.Y := Result.Y / Count;
  Result.Z := Result.Z / Count;
end;

{ X = Osten, Y = Norden -> Azimut = atan2(Nx, Ny), gemessen von Norden im
  Uhrzeigersinn: 0=N, 90=O, 180=S, 270=W }
function TPolygon.Azimuth: Double;
var
  N: TPoint3D;
begin
  N := Normal;

  { Bei einer horizontalen Fläche (Dach/Boden) gibt es keine sinnvolle
    Himmelsrichtung. }
  if Sqrt(N.X * N.X + N.Y * N.Y) < 0.000001 then
  begin
    Result := 0;
    Exit;
  end;

  Result := RadToDeg(ArcTan2(N.X, N.Y));

  if Result < 0 then
    Result := Result + 360.0;
end;

{ Tilt = Winkel zwischen Normale und "oben" (Z-Achse):
  0° = horizontal nach oben (Dach), 90° = senkrecht (Wand), 180° = nach unten (Boden) }
function TPolygon.Tilt: Double;
var
  N: TPoint3D;
begin
  N := Normal;
  Result := RadToDeg(ArcCos(Max(-1.0, Min(1.0, N.Z))));
end;

end.
