{ ============================================================================
  uGbXML.pas

  Import von Gebäudegeometrie aus gbXML-Dateien (Green Building XML), einem
  verbreiteten Austauschformat für Gebäudegeometrie und einfache Bauphysik.

  Umgesetzt werden Räume (<Space>), Flächen (<Surface>) mit ihrer Geometrie
  (<PlanarGeometry>/<PolyLoop>) und Öffnungen (<Opening>), sowie die
  Zuordnung jeder Fläche zu ein oder zwei Räumen über <AdjacentSpaceId>
  (ein Eintrag = Außenfläche, zwei Einträge = Innenfläche zwischen zwei
  Räumen).

  U-Werte werden - anders als ursprünglich im Gespräch vorgesehen ("nach
  einem erfolgreichen Geometrie-Import") - inzwischen doch aus gbXML
  übernommen, aber bewusst nur der pauschale U-Wert je <Construction>
  (Attribut "constructionIdRef" auf <Surface>/<Opening>, Element
  <U-value>), NICHT die feinere Schichtstruktur aus <Layer>/<Material>
  (Dicke/Leitfähigkeit/Dichte/spezifische Wärme je Schicht). Das genügt für
  den in diesem Projekt verwendeten Einzonen-Überschlagsansatz (ein
  einziger Widerstandspfad pro Fläche, siehe uRCBuilder.pas), auch wenn
  manche gbXML-Dateien (z. B. aus DDScad-Export) durchaus vollständige
  Materialschichten mitliefern - siehe README, Abschnitt zum gbXML-basierten
  Wärmebilanz-Werkzeug.

  Verwendet die freien FCL-XML-Units "DOM" und "XMLRead" (das sind die
  Fassung, aus der Lazarus seine Laz2_DOM/Laz2_XMLRead-Units ableitet - für
  ein reines Free-Pascal-Kommandozeilenprojekt ohne Lazarus sind DOM/XMLRead
  die richtige Wahl).
  ============================================================================ }
unit uGbXML;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  DOM, XMLRead,
  uGeometry,
  uBuilding,
  uBuildingGenerator;

type

  TgbXMLImporter = class
  private
    FDocument: TXMLDocument;

    FSpaceMap: TStringList;   // ID -> TRoom
    FSurfaceMap: TStringList; // ID -> TSurface

    { ID -> U-Wert (W/(m²K)), als String über TStringList.Values gepflegt -
      siehe ReadConstructions/LookupConstructionUValue. }
    FConstructionMap: TStringList;

    FMessages: TStringList;   // Warn-/Fehlermeldungen des letzten Imports

    procedure ReadConstructions;
    function LookupConstructionUValue(const ConstructionID: string;
      out UValue: Double): Boolean;

    procedure ReadSpaces(Building: TBuilding);
    procedure ReadSurfaces(Building: TBuilding);
    procedure ReadSurfaceGeometry(SurfaceNode: TDOMNode; Surface: TSurface);
    procedure ReadOpenings(SurfaceNode: TDOMNode; Surface: TSurface;
      Building: TBuilding);
    procedure ResolveSurfaceAdjacency(SurfaceNode: TDOMNode; Surface: TSurface;
      Building: TBuilding);
    procedure ApplyConstruction(Node: TDOMNode; Surface: TSurface;
      DefaultUValue: Double);

    procedure Warn(const Code, SourceID, Text: string);
  public
    constructor Create;
    destructor Destroy; override;

    { Lädt eine gbXML-Datei und füllt das übergebene (bereits erzeugte)
      TBuilding mit Räumen und Flächen. Liefert False, wenn die Datei nicht
      gelesen werden konnte. }
    function LoadFromFile(const FileName: string; Building: TBuilding): Boolean;

    property Messages: TStringList read FMessages;
  end;


{ Bildet den gbXML-"surfaceType" auf unseren TSurfaceKind ab. }
function MapSurfaceType(const Value: string): TSurfaceKind;

{ Bildet den gbXML-"openingType" auf unseren TSurfaceKind ab. }
function MapOpeningType(const Value: string): TSurfaceKind;

implementation

{ ---------------------------------------------------------------------------
  Kleine XML-Hilfsfunktionen.

  gbXML-Dateien werden von unterschiedlichen Werkzeugen teils mit,
  teils ohne Namespace-Präfix exportiert (<Surface> vs. <gb:Surface>);
  LocalName entfernt ein eventuelles Präfix, damit beide Fälle gleich
  behandelt werden.
  --------------------------------------------------------------------------- }

function LocalName(Node: TDOMNode): string;
begin
  Result := Node.NodeName;

  if Pos(':', Result) > 0 then
    Result := Copy(Result, Pos(':', Result) + 1, MaxInt);
end;

function GetAttrDef(Node: TDOMNode; const Name: string;
  const DefaultValue: string): string;
var
  A: TDOMNode;
begin
  Result := DefaultValue;

  if (Node = nil) or (Node.Attributes = nil) then
    Exit;

  A := Node.Attributes.GetNamedItem(Name);

  if A <> nil then
    Result := A.NodeValue;
end;

function FindChild(Node: TDOMNode; const Name: string): TDOMNode;
var
  I: Integer;
begin
  Result := nil;

  if Node = nil then
    Exit;

  for I := 0 to Node.ChildNodes.Count - 1 do
    if SameText(LocalName(Node.ChildNodes[I]), Name) then
    begin
      Result := Node.ChildNodes[I];
      Exit;
    end;
end;

procedure FindChildren(Node: TDOMNode; const Name: string; ResultList: TFPList);
var
  I: Integer;
begin
  if Node = nil then
    Exit;

  for I := 0 to Node.ChildNodes.Count - 1 do
    if SameText(LocalName(Node.ChildNodes[I]), Name) then
      ResultList.Add(Node.ChildNodes[I]);
end;

function FindChildText(Node: TDOMNode; const Name: string;
  const DefaultValue: string): string;
var
  Child: TDOMNode;
begin
  Result := DefaultValue;

  Child := FindChild(Node, Name);

  if Child <> nil then
    Result := Trim(Child.TextContent);
end;

procedure FindElementsRecursive(Node: TDOMNode; const ElementName: string;
  ResultList: TFPList);
var
  I: Integer;
begin
  if Node = nil then
    Exit;

  if SameText(LocalName(Node), ElementName) then
    ResultList.Add(Node);

  for I := 0 to Node.ChildNodes.Count - 1 do
    FindElementsRecursive(Node.ChildNodes[I], ElementName, ResultList);
end;

function InvariantFormatSettings: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := ',';
end;

function ReadPoint3D(Node: TDOMNode): TPoint3D;
var
  Coordinates: array[0..2] of Double;
  Count: Integer;
  I: Integer;
  Child: TDOMNode;
  FS: TFormatSettings;
begin
  Coordinates[0] := 0;
  Coordinates[1] := 0;
  Coordinates[2] := 0;

  Count := 0;
  FS := InvariantFormatSettings;

  for I := 0 to Node.ChildNodes.Count - 1 do
  begin
    Child := Node.ChildNodes[I];

    if not SameText(LocalName(Child), 'Coordinate') then
      Continue;

    if Count < 3 then
    begin
      Coordinates[Count] := StrToFloatDef(Trim(Child.TextContent), 0, FS);
      Inc(Count);
    end;
  end;

  Result.X := Coordinates[0];
  Result.Y := Coordinates[1];
  Result.Z := Coordinates[2];
end;

procedure ReadPolyLoop(PolyLoop: TDOMNode; Polygon: TPolygon);
var
  I: Integer;
  Node: TDOMNode;
begin
  if PolyLoop = nil then
    Exit;

  for I := 0 to PolyLoop.ChildNodes.Count - 1 do
  begin
    Node := PolyLoop.ChildNodes[I];

    if SameText(LocalName(Node), 'CartesianPoint') then
      Polygon.AddPoint(ReadPoint3D(Node));
  end;
end;

{ ---------------------------------------------------------------------------
  Abbildung der gbXML-Typen auf TSurfaceKind
  --------------------------------------------------------------------------- }

function MapSurfaceType(const Value: string): TSurfaceKind;
begin
  if SameText(Value, 'ExteriorWall') then Exit(skExteriorWall);
  if SameText(Value, 'InteriorWall') then Exit(skInteriorWall);
  if SameText(Value, 'Roof') then Exit(skRoof);
  if SameText(Value, 'InteriorFloor') then Exit(skInteriorFloor);
  if SameText(Value, 'SlabOnGrade') then Exit(skGroundFloor);
  if SameText(Value, 'RaisedFloor') then Exit(skGroundFloor);
  if SameText(Value, 'Ceiling') then Exit(skCeiling);
  if SameText(Value, 'UndergroundWall') then Exit(skGroundWall);
  if SameText(Value, 'UndergroundSlab') then Exit(skGroundFloor);
  if SameText(Value, 'Shade') then Exit(skUnknown);

  Result := skUnknown;
end;

function MapOpeningType(const Value: string): TSurfaceKind;
begin
  if SameText(Value, 'FixedWindow') or SameText(Value, 'OperableWindow') then
    Exit(skWindow);

  if SameText(Value, 'FixedSkylight') or SameText(Value, 'OperableSkylight') then
    Exit(skSkylight);

  if SameText(Value, 'SlidingDoor') or SameText(Value, 'NonSlidingDoor') then
    Exit(skDoor);

  Result := skOpening;
end;

{ TgbXMLImporter }

constructor TgbXMLImporter.Create;
begin
  inherited Create;

  FDocument := nil;

  FSpaceMap := TStringList.Create;
  FSurfaceMap := TStringList.Create;
  FConstructionMap := TStringList.Create;
  FMessages := TStringList.Create;

  FSpaceMap.Sorted := False;
  FSurfaceMap.Sorted := False;
  FConstructionMap.Sorted := False;
end;

destructor TgbXMLImporter.Destroy;
begin
  FDocument.Free;

  FSpaceMap.Free;
  FSurfaceMap.Free;
  FConstructionMap.Free;
  FMessages.Free;

  inherited Destroy;
end;

procedure TgbXMLImporter.Warn(const Code, SourceID, Text: string);
begin
  FMessages.Add(Format('WARNING [%s] %s: %s', [Code, SourceID, Text]));
end;

{ Manche gbXML-Exporte (beobachtet z. B. bei aus DDScad exportierten
  Fenster-/Tür-Constructions) lassen das <U-value>-Element aus, kodieren den
  U-Wert aber als Zahl am Ende der Construction-ID (z. B.
  "co-AF075..._1.2" -> 1,2 W/(m²K)) - bei den Bauteilen, die in derselben
  Datei sowohl ein <U-value> ALS AUCH diese Endung haben (Außenwand, Boden,
  Decke, Dach), stimmen beide exakt überein, was diese Interpretation
  stützt. Trotzdem ist das eine Interpretation einer nicht dokumentierten,
  werkzeugspezifischen Namenskonvention, keine offizielle gbXML-Angabe -
  wird deshalb nur als letzter Rückfall vor dem generischen Platzhalter
  verwendet, und jede Verwendung wird protokolliert. }
function TryExtractUValueFromConstructionID(const ID: string;
  out UValue: Double): Boolean;
var
  P: Integer;
  Suffix: string;
begin
  Result := False;
  UValue := 0;

  P := LastDelimiter('_', ID);
  if (P <= 0) or (P >= Length(ID)) then
    Exit;

  Suffix := Copy(ID, P + 1, MaxInt);
  Result := TryStrToFloat(Suffix, UValue, InvariantFormatSettings) and (UValue > 0);

  if not Result then
    UValue := 0;
end;

{ Liest alle <Construction>-Elemente (unabhängig davon, wo im Dokument sie
  stehen) und merkt sich deren U-Wert unter der ID - das reicht für unseren
  Einzonen-Überschlagsansatz; <LayerId>-Verweise auf <Layer>/<Material>
  (vollständige Schichtstruktur mit Dicke/Leitfähigkeit/Dichte/spezifischer
  Wärme) werden bewusst nicht ausgewertet, siehe Unit-Kopfkommentar. }
procedure TgbXMLImporter.ReadConstructions;
var
  Nodes: TFPList;
  I: Integer;
  Node: TDOMNode;
  ID: string;
  UValueNode: TDOMNode;
  UValue: Double;
begin
  FConstructionMap.Clear;

  Nodes := TFPList.Create;
  try
    FindElementsRecursive(FDocument.DocumentElement, 'Construction', Nodes);

    for I := 0 to Nodes.Count - 1 do
    begin
      Node := TDOMNode(Nodes[I]);

      ID := GetAttrDef(Node, 'id', '');
      if ID = '' then
        Continue;

      UValueNode := FindChild(Node, 'U-value');
      if UValueNode = nil then
      begin
        if TryExtractUValueFromConstructionID(ID, UValue) then
          Warn('GBXML_CONSTRUCTION_UVALUE_FROM_ID', ID,
            Format('kein <U-value>-Element - U-Wert %.3f W/(m²K) aus der ID-Endung übernommen (ungeprüfte Annahme, bitte kontrollieren).',
              [UValue]))
        else
        begin
          Warn('GBXML_CONSTRUCTION_NO_UVALUE', ID,
            'Construction ohne <U-value> und ohne auswertbare ID-Endung - Layer/Material-Schichtaufbau wird nicht ausgewertet.');
          Continue;
        end;
      end
      else
      begin
        UValue := StrToFloatDef(Trim(UValueNode.TextContent), -1, InvariantFormatSettings);
        if UValue <= 0 then
        begin
          Warn('GBXML_CONSTRUCTION_BAD_UVALUE', ID,
            Format('U-value "%s" ist keine plausible Zahl > 0.', [Trim(UValueNode.TextContent)]));
          Continue;
        end;
      end;

      { ID darf kein '=' enthalten (TStringList.Values-Konvention Name=Wert) -
        bei gbXML-IDs in der Praxis nicht zu erwarten. }
      FConstructionMap.Values[ID] := FloatToStr(UValue, InvariantFormatSettings);
    end;
  finally
    Nodes.Free;
  end;
end;

function TgbXMLImporter.LookupConstructionUValue(const ConstructionID: string;
  out UValue: Double): Boolean;
var
  S: string;
begin
  Result := False;
  UValue := 0;

  if ConstructionID = '' then
    Exit;

  S := FConstructionMap.Values[ConstructionID];
  if S = '' then
    Exit;

  Result := TryStrToFloat(S, UValue, InvariantFormatSettings);
end;

{ Setzt Surface.UValue (und bei transparenten Flächen SolarGValue) aus der
  über constructionIdRef referenzierten <Construction>. Ist kein Verweis
  vorhanden oder nicht auflösbar, wird DefaultUValue verwendet (wie bisher)
  und eine Warnung ausgegeben - der Import bricht dafür nicht ab. }
procedure TgbXMLImporter.ApplyConstruction(Node: TDOMNode; Surface: TSurface;
  DefaultUValue: Double);
var
  ConstructionID: string;
  UValue: Double;
begin
  ConstructionID := GetAttrDef(Node, 'constructionIdRef', '');

  if (ConstructionID <> '') and LookupConstructionUValue(ConstructionID, UValue) then
    Surface.UValue := UValue
  else
  begin
    if ConstructionID = '' then
      Warn('GBXML_NO_CONSTRUCTION_REF', Surface.ID,
        Format('kein constructionIdRef - verwende Platzhalter-U-Wert %.2f W/(m²K).', [DefaultUValue]))
    else
      Warn('GBXML_UNRESOLVED_CONSTRUCTION', Surface.ID,
        Format('constructionIdRef "%s" nicht auflösbar - verwende Platzhalter-U-Wert %.2f W/(m²K).',
          [ConstructionID, DefaultUValue]));

    Surface.UValue := DefaultUValue;
  end;

  if Surface.IsTransparent then
    Surface.SolarGValue := EstimateWindowSolarGValue(Surface.UValue);
end;

procedure TgbXMLImporter.ReadSpaces(Building: TBuilding);
var
  Nodes: TFPList;
  I: Integer;
  Node: TDOMNode;
  ID, Name: string;
  Room: TRoom;
begin
  Nodes := TFPList.Create;
  try
    FindElementsRecursive(FDocument.DocumentElement, 'Space', Nodes);

    for I := 0 to Nodes.Count - 1 do
    begin
      Node := TDOMNode(Nodes[I]);

      ID := GetAttrDef(Node, 'id', '');
      if ID = '' then
        Continue;

      Name := FindChildText(Node, 'Name', ID);

      Room := TRoom.Create;
      Room.ID := ID;
      Room.Name := Name;

      Room.GeometryVolume :=
        StrToFloatDef(FindChildText(Node, 'Volume', '0'), 0,
          InvariantFormatSettings);
      Room.UpdateGeometry;

      Room.FloorArea := StrToFloatDef(FindChildText(Node, 'Area', '0'), 0,
        InvariantFormatSettings);

      if Room.Volume <= 0 then
        Room.Volume := Room.FloorArea * 2.5; // grobe Schätzung, falls kein Volumen angegeben

      { Manche gbXML-Exporte geben eine reale, raumspezifische Solltemperatur
        an (z. B. 8°C für einen unbeheizten Flur/Keller) - 0 bedeutet
        "nicht angegeben", dann wird der Raum später (siehe
        uGbXMLAnalysis.AggregateToSingleZone) als beheizt angenommen. }
      Room.DesignTemperature := StrToFloatDef(FindChildText(Node, 'Temperature', '0'), 0,
        InvariantFormatSettings);

      Building.AddRoom(Room);

      FSpaceMap.AddObject(ID, Room);
    end;
  finally
    Nodes.Free;
  end;
end;

procedure TgbXMLImporter.ReadSurfaceGeometry(SurfaceNode: TDOMNode;
  Surface: TSurface);
var
  Geometry, PolyLoop: TDOMNode;
begin
  Geometry := FindChild(SurfaceNode, 'PlanarGeometry');
  if Geometry = nil then
  begin
    Warn('GBXML_SURFACE_NO_GEOMETRY', Surface.ID,
      'Surface besitzt keine PlanarGeometry.');
    Exit;
  end;

  PolyLoop := FindChild(Geometry, 'PolyLoop');
  if PolyLoop = nil then
    Exit;

  ReadPolyLoop(PolyLoop, Surface.Polygon);
end;

procedure TgbXMLImporter.ResolveSurfaceAdjacency(SurfaceNode: TDOMNode;
  Surface: TSurface; Building: TBuilding);
var
  Refs: TFPList;
  I: Integer;
  SpaceID: string;
  Room: TRoom;
begin
  Refs := TFPList.Create;
  try
    FindChildren(SurfaceNode, 'AdjacentSpaceId', Refs);

    for I := 0 to Refs.Count - 1 do
    begin
      SpaceID := GetAttrDef(TDOMNode(Refs[I]), 'spaceIdRef', '');
      Room := Building.FindRoom(SpaceID);

      if Room = nil then
      begin
        Warn('GBXML_UNKNOWN_SPACE', Surface.ID,
          'AdjacentSpaceId "' + SpaceID + '" verweist auf keinen bekannten Raum.');
        Continue;
      end;

      if I = 0 then
        Surface.SideA.Space := Room
      else if I = 1 then
      begin
        Surface.SideB := TSurfaceSide.Create;
        Surface.SideB.Space := Room;
      end;
    end;

    { Eine Fläche mit nur einer AdjacentSpaceId ist eine Außenfläche;
      mit zweien eine Innenfläche zwischen zwei Räumen. }
    Surface.IsExterior := Refs.Count <= 1;
  finally
    Refs.Free;
  end;
end;

procedure TgbXMLImporter.ReadOpenings(SurfaceNode: TDOMNode; Surface: TSurface;
  Building: TBuilding);
var
  I: Integer;
  Node: TDOMNode;
  Opening: TSurface;
  OpeningType: string;
begin
  for I := 0 to SurfaceNode.ChildNodes.Count - 1 do
  begin
    Node := SurfaceNode.ChildNodes[I];

    if not SameText(LocalName(Node), 'Opening') then
      Continue;

    Opening := TSurface.Create;

    Opening.ID := GetAttrDef(Node, 'id', '');
    Opening.Name := FindChildText(Node, 'Name', Opening.ID);
    Opening.SourceID := Opening.ID;
    Opening.SourceFormat := sfGbXML;

    OpeningType := GetAttrDef(Node, 'openingType', '');
    Opening.Kind := MapOpeningType(OpeningType);

    Opening.IsExterior := Surface.IsExterior;
    Opening.IsTransparent := Opening.Kind in [skWindow, skSkylight];

    if Opening.IsTransparent then
      Opening.ShadingFactor := 1.0;

    { SideA der Öffnung entspricht der SideA der tragenden Fläche - eine
      Öffnung "gehört" demselben Raum wie die Wand, in der sie sitzt. }
    Opening.SideA.Space := Surface.SideA.Space;

    { 1.4 W/(m²K) als Rückfallwert, falls kein/kein auflösbarer
      constructionIdRef vorhanden ist - wie zuvor, jetzt aber über
      ApplyConstruction auch für echte U-Werte aus der Datei nutzbar. Für
      nicht-transparente Öffnungen (z. B. openingType "Air", eine reine
      Luftverbindung ohne Bauteil) bleibt der U-Wert unbenutzt. }
    if Opening.IsTransparent then
      ApplyConstruction(Node, Opening, 1.4);

    ReadSurfaceGeometry(Node, Opening);
    Opening.UpdateGeometry;

    Surface.AddOpening(Opening);
    Building.AddSurface(Opening);

    FSurfaceMap.AddObject(Opening.ID, Opening);
  end;
end;

procedure TgbXMLImporter.ReadSurfaces(Building: TBuilding);
var
  Nodes: TFPList;
  I: Integer;
  Node: TDOMNode;
  Surface: TSurface;
  ID, SurfaceType: string;
begin
  Nodes := TFPList.Create;
  try
    FindElementsRecursive(FDocument.DocumentElement, 'Surface', Nodes);

    for I := 0 to Nodes.Count - 1 do
    begin
      Node := TDOMNode(Nodes[I]);

      ID := GetAttrDef(Node, 'id', '');
      if ID = '' then
        Continue;

      SurfaceType := GetAttrDef(Node, 'surfaceType', '');

      Surface := TSurface.Create;

      Surface.ID := ID;
      Surface.Name := FindChildText(Node, 'Name', ID);
      Surface.SourceID := ID;
      Surface.SourceFormat := sfGbXML;

      Surface.Kind := MapSurfaceType(SurfaceType);

      if Surface.Kind = skUnknown then
        Warn('GBXML_UNKNOWN_SURFACE_TYPE', ID,
          'surfaceType "' + SurfaceType + '" wird nicht unterstützt.');

      { 1.0 W/(m²K) als grober, neutraler Rückfallwert (etwa zwischen
        Altbau- und Neubau-Wandwert, siehe uInsulationStandards.pas) für
        opake Flächen ohne auflösbaren constructionIdRef - kommt in der
        Praxis nur bei unvollständigen gbXML-Exporten vor, siehe Warnung. }
      ApplyConstruction(Node, Surface, 1.0);

      ResolveSurfaceAdjacency(Node, Surface, Building);
      ReadSurfaceGeometry(Node, Surface);
      Surface.UpdateGeometry;

      Building.AddSurface(Surface);
      FSurfaceMap.AddObject(ID, Surface);

      { Öffnungen erst nachdem die Fläche selbst (inkl. SideA) bekannt ist }
      ReadOpenings(Node, Surface, Building);
    end;
  finally
    Nodes.Free;
  end;
end;

function TgbXMLImporter.LoadFromFile(const FileName: string;
  Building: TBuilding): Boolean;
begin
  Result := False;

  if Building = nil then
    Exit;

  if not FileExists(FileName) then
  begin
    Warn('GBXML_FILE_NOT_FOUND', FileName, 'Datei nicht gefunden.');
    Exit;
  end;

  FMessages.Clear;

  try
    ReadXMLFile(FDocument, FileName);
  except
    on E: Exception do
    begin
      Warn('GBXML_PARSE_ERROR', FileName, E.Message);
      Exit;
    end;
  end;

  if (FDocument = nil) or (FDocument.DocumentElement = nil) then
  begin
    Warn('GBXML_EMPTY_DOCUMENT', FileName, 'Kein gültiges XML-Dokument.');
    Exit;
  end;

  ReadConstructions;
  ReadSpaces(Building);
  ReadSurfaces(Building);

  Result := True;
end;

end.
