{ ============================================================================
  Tests.lpr

  Automatisierte Tests, angelehnt an die im Gespräch skizzierten drei
  Teststufen:
    Test 1 - Geometrie: ein Polygon -> Fläche, Normale, Ausrichtung, Neigung
    Test 2 - RC-Grundmodell: zwei Knoten, ein Widerstand, Angleichung der
             Temperatur über die Zeit
    Test 3 - gbXML-Import: unser kleines Testgebäude (test_house.gbxml)
             -> 1 Raum, 6 Flächen + 1 Fenster, korrekte Flächen/Normalen,
             und ein daraus erzeugtes RC-Modell mit Knoten > 0

  Bricht mit einer Fehlermeldung und Exitcode 1 ab, sobald eine Prüfung
  fehlschlägt; gibt andernfalls "ALLE TESTS BESTANDEN" aus.
  ============================================================================ }
program Tests;

{$mode objfpc}{$H+}

uses
  SysUtils, Math,
  uGeometry,
  uConstruction,
  uBuilding,
  uRCModel,
  uRCBuilder,
  uGbXML;

var
  FailCount: Integer = 0;

procedure Check(Condition: Boolean; const Name: string);
begin
  if Condition then
    WriteLn('  [OK]   ', Name)
  else
  begin
    WriteLn('  [FAIL] ', Name);
    Inc(FailCount);
  end;
end;

procedure CheckNear(Actual, Expected: Double; const Name: string;
  Tolerance: Double = 0.01);
begin
  Check(Abs(Actual - Expected) < Tolerance,
    Format('%s (erwartet %.4f, erhalten %.4f)', [Name, Expected, Actual]));
end;

{ Wie CheckNear, aber sucht die Fläche zuerst per ID - schlägt kontrolliert
  fehl (statt mit einer Zugriffsverletzung abzustürzen), wenn eine Datei
  ohne diese ID importiert wird, z. B. eine andere gbXML-Datei als unser
  kleines Testgebäude (siehe Test 3). }
procedure CheckSurfaceArea(Building: TBuilding; const SurfaceID: string;
  ExpectedArea: Double; const Name: string);
var
  Surface: TSurface;
begin
  Surface := Building.FindSurface(SurfaceID);
  Check(Surface <> nil, Name + ' (Fläche "' + SurfaceID + '" vorhanden)');
  if Surface <> nil then
    CheckNear(Surface.Area, ExpectedArea, Name);
end;

{ -------------------------------------------------------------------------
  Test 1: Geometrie
  ------------------------------------------------------------------------- }
procedure TestGeometry;
var
  Poly: TPolygon;
begin
  WriteLn('Test 1: Geometrie (TPolygon)');

  { Ein 5x5 m Quadrat in der horizontalen Ebene (Boden/Dach) }
  Poly := TPolygon.Create;
  try
    Poly.AddPoint(Point3D(0, 0, 0));
    Poly.AddPoint(Point3D(5, 0, 0));
    Poly.AddPoint(Point3D(5, 5, 0));
    Poly.AddPoint(Point3D(0, 5, 0));

    CheckNear(Poly.Area, 25.0, 'Fläche des 5x5m Quadrats');
    CheckNear(Poly.Tilt, 0.0, 'Neigung einer horizontalen Fläche (0° = Dach)');
  finally
    Poly.Free;
  end;

  { Eine 5 m breite, 2,8 m hohe Südwand bei Y=0 (Normale zeigt nach Süden,
    also in -Y-Richtung -> Azimut 180°) }
  Poly := TPolygon.Create;
  try
    Poly.AddPoint(Point3D(0, 0, 0));
    Poly.AddPoint(Point3D(5, 0, 0));
    Poly.AddPoint(Point3D(5, 0, 2.8));
    Poly.AddPoint(Point3D(0, 0, 2.8));

    CheckNear(Poly.Area, 14.0, 'Fläche der Südwand (5 x 2,8 m)');
    CheckNear(Poly.Tilt, 90.0, 'Neigung einer senkrechten Wand');
    CheckNear(Poly.Normal.Y, -1.0, 'Süd-Normale zeigt in -Y', 0.001);
    CheckNear(Poly.Azimuth, 180.0, 'Ausrichtung der Südwand (180° = Süd)');
  finally
    Poly.Free;
  end;

  WriteLn;
end;

{ -------------------------------------------------------------------------
  Test 2: RC-Grundmodell
  ------------------------------------------------------------------------- }
procedure TestRCModel;
var
  Model: TRCModel;
  A, B: TRCNode;
  I: Integer;
begin
  WriteLn('Test 2: RC-Grundmodell');

  Model := TRCModel.Create;
  try
    A := Model.AddNode('A', 'Knoten A', nkRoom);
    A.Temperature := 20.0;
    A.HeatCapacity := 1000.0;

    B := Model.AddNode('B', 'Knoten B', nkOutside);
    B.Temperature := 0.0;
    B.HeatCapacity := 0.0;  // fester Knoten, wie die Außenluft

    Model.AddLink('R', 'Widerstand', A, B, 1.0, lkUnknown);

    { 500 Schritte à 1 s: A muss sich der (festen) Temperatur von B nähern }
    for I := 1 to 500 do
      Model.Step(1.0);

    Check(A.Temperature < 20.0, 'Knoten A kühlt sich in Richtung B ab');
    Check(A.Temperature > B.Temperature, 'Knoten A bleibt über der Außentemperatur');
    Check(Model.NodeCount = 2, 'Modell enthält 2 Knoten');
    Check(Model.LinkCount = 1, 'Modell enthält 1 Verbindung');
  finally
    Model.Free;
  end;

  WriteLn;
end;

{ -------------------------------------------------------------------------
  Test 3: gbXML-Import (unser kleines Testgebäude)
  ------------------------------------------------------------------------- }
procedure TestGbXMLImport;
var
  Building: TBuilding;
  Importer: TgbXMLImporter;
  Model: TRCModel;
  Builder: TRCModelBuilder;
  SouthWall: TSurface;
  FileName: string;
  I: Integer;
begin
  WriteLn('Test 3: gbXML-Import (test_house.gbxml)');

  FileName := ExtractFilePath(ParamStr(0)) + '../data/test_house.gbxml';
  if not FileExists(FileName) then
    FileName := 'data/test_house.gbxml';
  if not FileExists(FileName) then
    FileName := '../data/test_house.gbxml';

  Building := TBuilding.Create;
  Importer := TgbXMLImporter.Create;
  try
    Check(Importer.LoadFromFile(FileName, Building), 'gbXML-Datei erfolgreich geladen: ' + FileName);

    for I := 0 to Importer.Messages.Count - 1 do
      WriteLn('    ', Importer.Messages[I]);

    Check(Building.Rooms.Count = 1, 'genau 1 Raum importiert');
    { 6 Bauteilflächen (Süd/Nord/Ost/West/Dach/Boden) + 1 Fenster, das der
      RC-Builder als eigene, parallele Fläche braucht (siehe uGbXML.pas) }
    Check(Building.Surfaces.Count = 7, '6 Flächen + 1 Fenster importiert');

    SouthWall := Building.FindSurface('Surface_South');
    Check(SouthWall <> nil, 'Südwand gefunden');

    if SouthWall <> nil then
    begin
      CheckNear(SouthWall.Area, 14.0, 'Südwand-Bruttofläche');
      Check(SouthWall.OpeningCount = 1, 'Südwand hat 1 Öffnung (Fenster)');

      if SouthWall.OpeningCount = 1 then
        CheckNear(SouthWall.Opening(0).Area, 2.25, 'Fensterfläche');

      CheckNear(SouthWall.NetArea, 11.75, 'Südwand-Nettofläche');
      CheckNear(SouthWall.Polygon.Normal.Y, -1.0, 'Süd-Normale zeigt nach Süden', 0.001);
    end;

    CheckSurfaceArea(Building, 'Surface_North', 14.0, 'Nordwandfläche');
    CheckSurfaceArea(Building, 'Surface_East', 14.0, 'Ostwandfläche');
    CheckSurfaceArea(Building, 'Surface_West', 14.0, 'Westwandfläche');
    CheckSurfaceArea(Building, 'Surface_Roof', 25.0, 'Dachfläche');
    CheckSurfaceArea(Building, 'Surface_Floor', 25.0, 'Bodenfläche');

    Builder := TRCModelBuilder.Create;
    Model := Builder.Build(Building);
    Builder.Free;
    try
      Check(Model.NodeCount > 0, 'aus dem Import erzeugtes RC-Modell enthält Knoten');
      WriteLn(Format('    -> RC-Modell: %d Knoten, %d Verbindungen',
        [Model.NodeCount, Model.LinkCount]));
    finally
      Model.Free;
    end;

  finally
    Importer.Free;
    Building.Free;
  end;

  WriteLn;
end;

begin
  TestGeometry;
  TestRCModel;
  TestGbXMLImport;

  WriteLn('----------------------------------------');
  if FailCount = 0 then
    WriteLn('ALLE TESTS BESTANDEN')
  else
  begin
    WriteLn(FailCount, ' TEST(S) FEHLGESCHLAGEN');
    ExitCode := 1;
  end;
end.
