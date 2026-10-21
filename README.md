# Gebäudesimulation (Free Pascal)

Dies ist die Zusammenführung des in `GebaeudeSimulation.docx` dokumentierten
Entwurfsgesprächs zu einer thermischen Gebäudesimulation in Object Pascal.
Das Gespräch entwickelt die Architektur über sehr viele Iterationen (Code
wird immer wieder verworfen, umbenannt und verfeinert); dieses Projekt nimmt
jeweils den letzten, tragfähigsten Stand jeder Komponente und fügt sie zu
einem einzigen, kompilierbaren und lauffähigen Free-Pascal-Projekt zusammen.

## Bauen und Ausführen

Voraussetzung: Free Pascal Compiler (`fpc`, getestet mit 3.2.2) sowie das
FCL-XML-Paket (stellt die Units `DOM`/`XMLRead` bereit; unter Debian/Ubuntu
z. B. `apt install fp-compiler fp-units-fcl`).

```
make               # baut src/Demo, src/Tests und src/Analyse
make run-demo      # Tagesgang-Simulation des Beispielgebäudes
make run-tests     # automatisierte Tests (Geometrie, RC-Modell, gbXML-Import)
make run-analyse   # Wärmebilanz-Analyse der Beispielgebäude in data/*.txt
```

Alle drei Programme sind eigenständige Kommandozeilenprogramme ohne weitere
Abhängigkeiten. `Analyse` kann außerdem direkt mit eigenen Gebäudebeschreibungen
aufgerufen werden (siehe unten):

```
./src/Analyse meinhaus.txt [weiteres_haus.txt ...]
```

## Projektstruktur

| Unit | Inhalt |
|---|---|
| `src/uGeometry.pas` | `TPoint3D`, Vektor-Operationen, `TPolygon` (Fläche/Normale/Azimut/Neigung aus echten 3D-Koordinaten) |
| `src/uConstruction.pas` | `TMaterial`, `TConstructionLayer`, `TConstruction` (Bauteilschichtaufbau) |
| `src/uBuilding.pas` | `TSurface` (Fläche mit Geometrie, Thermik, Öffnungen), `TRoom`, `TBuilding` |
| `src/uRCModel.pas` | Thermisches Ersatzschaltbild: `TRCNode`, `TRCLink`, `TRCModel` mit `Step()` |
| `src/uRCBuilder.pas` | `TRCModelBuilder`: erzeugt aus einem `TBuilding` automatisch ein `TRCModel` |
| `src/uWeather.pas` | `TWeatherState`, synthetisches Testwetter |
| `src/uSolar.pas` | Sonnenstand, solare Einstrahlung/Gewinn, `TSolarModel` |
| `src/uSimulation.pas` | `TRCHeatingController` (Zweipunktregler), `TRCSimulation` (verbindet alles) |
| `src/uGbXML.pas` | Import von Geometrie/Räumen/Öffnungen sowie U-Werten aus gbXML-Dateien |
| `src/uGbXMLAnalysis.pas` | Fasst ein mehrzoniges gbXML-Gebäude zu einer beheizten Einzone zusammen (`AggregateToSingleZone`), siehe unten |
| `src/uInsulationStandards.pas` | Baualtersklassen/Dämmstandards (Altbau … Passivhaus): U-Werte, Luftwechselrate, grobe Vergleichswerte für den Heizwärmebedarf |
| `src/uBuildingDescription.pas` | Liest die einfachen Text-Gebäudebeschreibungen (`Key: Value`) ein, siehe unten |
| `src/uBuildingGenerator.pas` | Erzeugt aus einer `TBuildingDescription` automatisch ein einfaches, quaderförmiges `TBuilding` (eine Zone) |
| `src/uHeatBalance.pas` | Stationäre Auslegungsheizlast aus einem `TRCModel`, spezifischer Heizwärmebedarf |
| `src/uTRYImport.pas` | Import echter Stundenwetterdaten aus einer DWD-TRY-Datei (Testreferenzjahr), siehe unten |
| `src/Demo.lpr` | Beispielgebäude (Wohnzimmer + Flur, Südwand mit Fenster), 24h-Simulation |
| `src/Tests.lpr` | Automatisierte Tests für Geometrie, RC-Modell und gbXML-Import |
| `src/Analyse.lpr` | Wärmebilanz-Werkzeug: liest Gebäudebeschreibungen ein und analysiert jedes Gebäude einzeln (Heizlast, Jahressimulation, Vergleichstabelle) |
| `data/test_house.gbxml` | Das im Gespräch entwickelte kleine Testgebäude als gbXML-Datei (nur für `Tests.lpr`) |
| `data/beispiel_reales_gebaeude.gbxml` | Ein echtes, aus DDScad MEP exportiertes Gebäude (10 Räume) mit realen U-Werten je Bauteil - siehe unten |
| `data/gebaeude_*.txt` | Fünf Beispiel-Gebäudebeschreibungen für `Analyse` (Altbau, Neubau, Passivhaus, Neubau mit TRY-Wetterdaten, reales Gebäude aus gbXML) |
| `data/TRY2026_synthetic_Testjahr.dat` | Synthetische Testdatei im TRY-Spaltenformat für `uTRYImport.pas` - **keine echten Messdaten**, siehe unten |

## Was gegenüber dem Gesprächstext ergänzt bzw. korrigiert wurde

Das Gespräch ist ein Entwurfsprozess, kein fertiges Programm - an mehreren
Stellen bleiben Ideen skizzenhaft oder ein späterer Absatz korrigiert einen
früheren, ohne dass beides konsistent zusammengeführt wird. Für ein
tatsächlich lauffähiges Projekt waren folgende (kleine, aber notwendige)
Ergänzungen nötig:

- **Synchrones Update in `TRCModel.Step`**: Das Gespräch bemerkt selbst,
  dass die erste Fassung ordnungsabhängig ist, und ersetzt sie durch eine
  synchrone Variante (alle Flüsse zuerst mit alten Temperaturen berechnen,
  dann alle Knoten gleichzeitig fortschreiben). Diese spätere Fassung wurde
  übernommen.
- **Interne Unterschritte in `TRCModel.Step`**: Ein Wandaufbau aus dünnen,
  gut leitenden Schichten (z. B. Putz) und einer dicken, schlecht leitenden
  Dämmschicht ergibt ein numerisch steifes Gleichungssystem. Ein einzelner
  5-Minuten-Zeitschritt (wie in der Demo verwendet) ist für das explizite
  Euler-Verfahren dafür zu groß und lief in ersten Tests tatsächlich
  sichtbar auseinander (Temperaturen liefen exponentiell weg). `Step()`
  zerlegt einen Aufruf deshalb intern automatisch in hinreichend kleine
  Teilschritte (siehe `MaxSubStepSeconds` in `uRCModel.pas`).
- **Keine masselosen Zwischenknoten mehr an den Bauteilrändern**: Eine
  frühere Fassung im Gespräch fügte zwischen Rsi/Rse und der ersten/letzten
  Materialschicht eigene "Oberflächenknoten" ohne Wärmekapazität ein und
  verband diese über einen Widerstand nahe Null mit dem Rest des Netzes -
  ein Workaround, der zusammen mit einem masselosen Knoten (dessen
  Temperatur der Solver nie aktualisiert) zu genau der oben beschriebenen
  Instabilität führt. `uRCBuilder.pas` verbindet Rsi/Rse jetzt direkt mit
  der ersten/letzten Materialschicht, ohne zusätzlichen Knoten.
- **Kleinere Tippfehler in den Solar-Formeln** (z. B. eine `var`-Deklaration
  ohne Typangabe in `SolarIrradianceOnSurface`) wurden stillschweigend
  korrigiert.
- **gbXML-Import**: Die im Gespräch gezeigten Bausteine (XML-Hilfsfunktionen,
  `TgbXMLImporter`, Flächen-/Öffnungs-Import) wurden übernommen und um die
  Adjazenzauflösung ergänzt (`<AdjacentSpaceId>`: ein Eintrag = Außenfläche,
  zwei Einträge = Innenfläche zwischen zwei Räumen), die im Gesprächstext nur
  als Diagramm skizziert, aber nicht ausprogrammiert war. Ursprünglich wurden
  Konstruktionen und U-/g-Werte bewusst nicht aus gbXML übernommen, da das
  erst nach einem belastbaren Geometrie-Import sinnvoll ist - mittlerweile
  liest der Import auch die realen `<Construction><U-value>`-Werte je
  Bauteil aus (Layer-/Material-Schichtaufbau weiterhin nicht), siehe
  "Wärmebilanz für ein echtes Gebäude" unten. Fenster ohne auflösbaren
  U-Wert erhalten weiterhin einen physikalisch plausiblen Platzhalterwert
  (U = 1,4 W/m²K, g wird aus dem tatsächlichen U-Wert grob geschätzt).
- **Fenster als eigene, parallele Fläche**: An einer Stelle im Gespräch wird
  ein Fenster nur als Öffnung geführt (nicht als eigene `TBuilding`-Fläche),
  an anderer Stelle zusätzlich auch als eigene Fläche hinzugefügt. Diese
  zweite, im ausführbaren `Demo`-Beispiel des Gesprächs tatsächlich
  verwendete Variante wurde übernommen: Wand und Fenster sind zwei
  parallele Widerstandspfade Raum↔Außenluft, die Wandkonstruktion nutzt die
  um die Fensterfläche reduzierte Nettofläche.
- **Absturz in `Tests.lpr` bei fremden gbXML-Dateien behoben**: Fünf der
  gbXML-Tests griffen ungeschützt auf `Building.FindSurface(...).Area` zu
  (anders als der direkt darüberstehende Test für die Südwand, der bereits
  korrekt auf `nil` prüfte). Bei einer gbXML-Datei ohne diese speziellen
  Test-Flächen-IDs (z. B. einer echten, nicht vom Projekt erzeugten Datei)
  liefert `FindSurface` `nil` zurück, und der Zugriff auf `.Area` stürzte
  mit einer Zugriffsverletzung ab, statt kontrolliert "nicht gefunden" gemäß
  `Check(...)` zu melden. Eine neue Hilfsprozedur `CheckSurfaceArea` prüft
  jetzt konsequent auf `nil`, bevor sie die Fläche vergleicht.

## Wärmebilanz-Erweiterung (`Analyse.lpr`)

Zusätzlich zur ursprünglichen Aufgabe (Zusammenführung des Gesprächs zu einem
lauffähigen Projekt) wurde das Projekt um ein zweites Kommandozeilenprogramm
erweitert: `Analyse` liest eine oder mehrere einfache Text-Gebäudebeschreibungen
ein und ermittelt für jedes Gebäude einzeln eine überschlägliche Wärmebilanz -
sowohl eine stationäre Auslegungsheizlast (grobes Kurzverfahren, angelehnt an
DIN EN 12831) als auch, über eine dynamische Jahressimulation mit synthetischem
Jahresklima, den spezifischen Heizwärmebedarf in kWh/(m²a). Am Ende steht eine
Vergleichstabelle aller übergebenen Gebäude.

### Format der Gebäudebeschreibung

Einfache Textdatei mit `Schlüssel: Wert`-Zeilen, eine Angabe pro Zeile.
Kommentare beginnen mit `#` oder `;`. Dezimalzahlen dürfen Punkt oder Komma
verwenden. Nicht erkannte oder unplausible Zeilen führen nicht zum Abbruch,
sondern erzeugen eine Warnung, die `Analyse` beim jeweiligen Gebäude mit
ausgibt. Alle Angaben sind optional - fehlende Werte werden durch plausible
Standardwerte ersetzt (siehe `DefaultBuildingDescription` in
`uBuildingDescription.pas`).

| Schlüssel | Bedeutung | Beispiel |
|---|---|---|
| `Name` | Bezeichnung des Gebäudes (nur für die Ausgabe) | `Einfamilienhaus Musterstraße 1` |
| `Baujahr` | Baujahr; dient als Fallback für den Dämmstandard, falls dieser nicht explizit angegeben ist | `1965` |
| `Daemmstandard` / `Dämmstandard` | Dämmstandard, überschreibt die aus dem Baujahr abgeleitete Klasse. Erkannte Werte (Groß-/Kleinschreibung egal): `Altbau_unsaniert`/`unsaniert`, `Altbau`, `WSVO1977`/`WSchV1977`, `WSVO1995`/`WSchV1995`, `EnEV2002`/`EnEV`, `EnEV2009`, `EnEV2016`/`GEG`/`Neubau`, `KfW55`/`KfW70`/`Effizienzhaus`, `Passivhaus`/`Passivhausstandard` | `EnEV2016` |
| `Grundflaeche` / `Grundfläche` | Grundfläche in m² (Alternative zu Länge/Breite) | `120` |
| `Laenge` / `Länge`, `Breite` | Gebäudelänge/-breite in m (Alternative zur Grundfläche, ergibt ein rechteckiges Gebäude) | `12` / `10` |
| `Hoehe` / `Höhe` / `Geschosshoehe` / `Geschosshöhe` | Geschosshöhe in m | `2.6` |
| `Stockwerke` / `Geschosse` | Anzahl der beheizten Geschosse | `2` |
| `Dachform` | `Flachdach`, `Satteldach` oder `Walmdach` (bestimmt nur einen Flächen-Zuschlagsfaktor auf die Dachfläche, siehe unten) | `Satteldach` |
| `Fensteranteil` | Fensteranteil je Fassadenseite in % der Wandfläche | `18` |
| `Luftwechselrate` | Luftwechselrate in 1/h; überschreibt den aus dem Dämmstandard abgeleiteten Wert | `0.4` |
| `Innentemperatur` | Beheizte Raum-/Solltemperatur in °C | `20` |
| `Aussentemperatur_Auslegung` / `Außentemperatur_Auslegung` | Winterliche Auslegungsaußentemperatur in °C (für die Heizlastberechnung) | `-12` |
| `Standort_Jahresmitteltemperatur` | Jahresmitteltemperatur des Standorts in °C (Grundlage für das synthetische Jahresklima und die angenommene Erdreichtemperatur - wird ignoriert, sobald eine `TRY_Datei` erfolgreich geladen wurde) | `9.5` |
| `Standort_Breitengrad`, `Standort_Laengengrad`, `Standort_Zeitzone` | Standort für die Sonnenstandsberechnung (`uSolar.pas`); Default entspricht Hamburg (53,43° N, 10,37° O, UTC+1) | `48.14` / `11.58` / `1` |
| `Uwert_Wand`, `Uwert_Dach`, `Uwert_Boden`, `Uwert_Fenster` | Einzelne U-Werte in W/(m²K), überschreiben die aus dem Dämmstandard abgeleiteten Werte | `0.20` |
| `TRY_Datei` | Pfad zu einer TRY-Wetterdatei (siehe unten). Relativer Pfad wird relativ zum Verzeichnis der Beschreibungsdatei aufgelöst. Fehlt der Schlüssel oder ist die Datei nicht lesbar, verwendet `Analyse` wie bisher das synthetische Jahresklima | `TRY2026_synthetic_Testjahr.dat` |

Vier Beispieldateien liegen in `data/` (`gebaeude_altbau.txt`,
`gebaeude_neubau.txt`, `gebaeude_passivhaus.txt`,
`gebaeude_mit_trywetter.txt`) und werden von `Analyse` ohne Argumente
automatisch verwendet.

### Wie aus der Beschreibung ein Gebäude wird - und was dabei vereinfacht ist

Die Textdatei beschreibt bewusst "nur in groben Zügen" ein Gebäude, wie in
der Anforderung formuliert. `uBuildingGenerator.pas` übersetzt das in ein
einzelnes, stark vereinfachtes `TBuilding`, damit es sich mit dem bestehenden
RC-Modell (`uRCModel.pas`/`uRCBuilder.pas`) simulieren lässt - dieselbe
Maschinerie, die auch `Demo.lpr` und den gbXML-Import antreibt. Konkret:

- **Eine einzige thermische Zone für das ganze Gebäude**, unabhängig von der
  Stockwerkszahl. Das ist eine bewusste, deutliche Vereinfachung: reale
  Gebäude mit sehr unterschiedlich genutzten oder orientierten Geschossen
  (z. B. beheizter Keller, unbeheiztes Dachgeschoss) werden dadurch nicht
  differenziert abgebildet, nur ein grober Gesamtdurchschnitt.
- **Rechteckiger Grundriss.** Bei Angabe von `Grundflaeche` (statt
  Länge/Breite) wird intern ein Quadrat gleicher Fläche angenommen.
- **Vier Fassadenwände** (Nord/Ost/Süd/West) je Geschoss, jede mit demselben
  Fensteranteil - eine feste Verteilung der Fensterfläche über die
  Himmelsrichtungen ist mit den wenigen Eingabewerten nicht abbildbar. Reale
  Gebäude haben praktisch immer eine ungleiche Verteilung (z. B. mehr Fenster
  nach Süden), was den solaren Wärmegewinn und die Verteilung der
  Transmissionsverluste beeinflusst.
- **Dachform wirkt nur als Flächen-Zuschlagsfaktor** auf die Dachfläche
  (Flachdach ×1,0, Satteldach ×1,15, Walmdach ×1,20), nicht als echte 3D-Geometrie
  mit Neigung und Ausrichtung.
- **Bodenplatte und Dach nur im untersten/obersten Geschoss**, mit derselben
  Grundfläche wie die übrigen Geschosse (kein Vor-/Rücksprung der Etagen).
- **Erdreich als zweiter fester Randknoten** (`nkGround` in `uRCModel.pas`):
  Bodenplatte und erdberührte Wände koppeln thermisch an einen festen Knoten
  auf Jahresmitteltemperatur des Standorts statt an die (stark schwankende)
  Außenlufttemperatur - physikalisch deutlich realistischer als eine direkte
  Kopplung an die Außenluft, aber immer noch eine grobe Näherung ohne
  saisonale Phasenverschiebung im Erdreich.
- **Pauschale Speichermasse** je Zone (`Room.ThermalMassCapacity`, angenommen
  165.000 J/(m²K) bezogen auf die Grundfläche, gekoppelt über einen
  angenommenen Wärmeübergangswiderstand), um dem Einzonenmodell überhaupt eine
  plausible thermische Trägheit zu geben - ohne diese wäre die Zone bei
  1-Stunden-Zeitschritten unrealistisch trägheitslos. Der Wert ist ein grober
  Anhaltswert für "mittelschwere" Bauweise, keine aus Bauteilschichten
  berechnete Größe.
- **U-Werte je Dämmstandard** (`uInsulationStandards.pas`) sind grobe,
  illustrative Anhaltswerte für Wand/Dach/Boden/Fenster und Luftwechselrate je
  Baualtersklasse - **keine geprüften Norm- oder Bestandsdaten**. Für eine
  belastbare Auslegung sind sie durch tatsächliche Bauteilaufbauten oder eine
  Energieberatung zu ersetzen; in der Textdatei können einzelne U-Werte
  deshalb auch direkt überschrieben werden (`Uwert_Wand` usw.).
- **Envelope-Flächen ohne Materialschichten**: anders als bei `Demo.lpr` (das
  echte `TConstruction`-Schichtaufbauten mit mehreren Materialknoten nutzt)
  bekommen die generierten Flächen nur einen einzigen U-Wert und werden im
  RC-Modell als ein einziger Widerstandspfad Raum↔Außenluft/Erdreich
  abgebildet (`uRCBuilder.pas`, der U-Wert-Pfad wurde dafür von "nur Fenster"
  auf "jede Fläche mit `UValue > 0`" verallgemeinert). Das ist ausreichend für
  eine überschlägliche Bilanz, bildet aber keine Wärmespeicherung *in* der
  Wand selbst ab (nur über die pauschale Zonen-Speichermasse oben).
- **Synthetisches Jahresklima** (`TClimateProfile` in `uWeather.pas`):
  Jahresgang als Kosinus um die angegebene Jahresmitteltemperatur, überlagert
  mit dem bereits vorhandenen Tagesgang - keine echten Klimadaten (z. B.
  Testreferenzjahr). Die ursprüngliche `GenerateTestWeather`-Funktion bleibt
  für `Demo`/`Tests` unverändert erhalten; das neue Jahresklima wird nur von
  `Analyse` genutzt.
- **Heizlastschätzung nur für direkte Anschlüsse an den Raumknoten**
  (`uHeatBalance.pas`): `EstimateDesignHeatLoad` summiert die Leitwerte aller
  Verbindungen, die direkt am Raumknoten hängen. Das ist für die hier
  generierten Gebäude (ohne Materialzwischenknoten) korrekt, würde bei einem
  Gebäude mit mehrschichtigen Bauteilen (wie `Demo.lpr`) aber nur den
  raumseitigen Übergangswiderstand erfassen, nicht den gesamten Bauteilaufbau
  - die Funktion ist deshalb bewusst nicht für `Demo.lpr` vorgesehen.
- **Heizungsregler bewusst überdimensioniert** (`MaxPower` = 2,5 × geschätzte
  Auslegungsheizlast) in der Jahressimulation, damit die ermittelte
  Jahres-Heizenergie die tatsächliche Wärmebilanz widerspiegelt und nicht
  durch eine zu knapp bemessene Heizleistung künstlich gedeckelt wird.
- Die in der Ausgabe angezeigte **Vergleichsspanne für den spezifischen
  Heizwärmebedarf** je Dämmstandard (`GetTypicalSpecificDemandRange`) ist ein
  grober Literatur-Anhaltswert zur Plausibilitätsprüfung, keine normative
  Referenz.

Kurz: `Analyse` liefert eine *überschlägliche* Wärmebilanz im Sinne der
Anforderung - für eine belastbare Energieberatung oder einen Nachweis (z. B.
GEG-Nachweis) ersetzt es keine Fachplanung mit echten Bauteilaufbauten,
Klimadaten und Mehrzonenmodell.

## Echte Wetterdaten statt synthetischem Klima (`uTRYImport.pas`)

Als weitere Erweiterung kann die Jahressimulation statt des synthetischen
Jahresklimas echte Stundenwerte aus einer DWD-TRY-Datei (Testreferenzjahr)
verwenden - Temperatur, Wind, Luftfeuchte sowie direkte/diffuse
Sonnenstrahlung auf der Horizontalen für jede der 8760 Stunden eines Jahres.
Dazu einfach `TRY_Datei: <Pfad>` in der Gebäudebeschreibung angeben (siehe
`data/gebaeude_mit_trywetter.txt`).

**Herkunft und was übernommen wurde:** Die Datenstruktur und der Import
(`uTRYImport.pas`) basieren auf zwei bereitgestellten Dateien,
`pWeatherRecord.pas` und `pImportRefYear.pas` - insbesondere deren
Spaltenzuordnung beim Einlesen (welcher Tokenindex welcher physikalischen
Größe entspricht) wurde unverändert übernommen, da sie vermutlich gegen
echte TRY-Dateien entwickelt wurde und ohne eine solche Referenzdatei nicht
unabhängig nachvollzogen werden kann. Angepasst wurden nur technische
Aspekte: FPC-taugliche Unit-Namen statt der Delphi-Scopes
(`System.Classes` usw.), kein globaler Zustand mehr (`LoadTRYYear` liefert
einen eigenständigen `TTRYYear`-Record statt eines globalen `var
ReferenceYear`, damit mehrere Gebäude mit unterschiedlichen TRY-Dateien in
einem Programmlauf verarbeitet werden können), ein robuster
Whitespace-Tokenizer statt `TStrings.DelimitedText` mit dem (in der Vorlage
nie geänderten) Komma als Trennzeichen, sowie eine `Warnings`-Liste statt
eines abbrechenden `StrToInt`/`StrToFloat` bei fehlerhaften Zeilen -
konsistent mit dem Rest des Projekts (`uBuildingDescription.pas`).

**Bewusst NICHT übernommen** (siehe Rückfrage/Antwort zu dieser Erweiterung):
die parallele, interface-basierte Fassung `pReferenceYear(.Intf).pas` -
weitgehend nur leere Methodenrümpfe und redundant zu
`pWeatherRecord`/`pImportRefYear` - sowie `pSunCalculations(.Intf).pas`
(Sonnenstand/Bestrahlung geneigter Flächen), das ebenfalls fast nur aus
Signaturen ohne Berechnungslogik besteht. Für die Umrechnung der TRY-
Direktstrahlung (siehe unten) wird stattdessen die bereits im Projekt
vorhandene, vollständige Sonnenstandsberechnung aus `uSolar.pas`
wiederverwendet.

**Notwendige Ergänzung - Umrechnung der Direktstrahlung:** TRY-Dateien
liefern die direkte Sonnenstrahlung (B) auf der Horizontalen, das
vorhandene Solarmodell (`uSolar.pas`) erwartet aber die
Direktnormalstrahlung (senkrecht zur Sonne). `uSimulation.pas` rechnet das
mit dem ohnehin für die Fenster-Einstrahlung berechneten Sonnenstand um:
`DNI = B_horizontal / sin(Sonnenhöhe)`, wobei unterhalb von 3° Sonnenhöhe
(Dämmerung/streifender Einfall) 0 angenommen wird, um eine Division durch
(nahe) Null und unrealistische Spitzenwerte zu vermeiden - ein in der
Praxis übliches, einfaches Vorgehen.

**Weitere Vereinfachungen/offene Punkte dieser Erweiterung:**

- Die in TRY-Dateien enthaltenen Metadaten TRY-Region und
  Standortinformation werden derzeit nicht ausgewertet bzw. nicht auf
  echte Koordinaten abgebildet (dafür wäre eine Tabelle der 15
  DWD-TRY-Regionen mit ihren jeweiligen Referenzkoordinaten nötig). Der
  Standort für die Sonnenstandsberechnung kommt stattdessen aus den neuen,
  unabhängig setzbaren Schlüsseln `Standort_Breitengrad` /
  `Standort_Laengengrad` / `Standort_Zeitzone` in der Beschreibungsdatei
  (Default: Hamburg, wie zuvor `TSolarModel.Create`) - diese müssen bei
  Verwendung einer TRY-Datei aus einer anderen Region von Hand passend
  gesetzt werden.
- Wind und relative Luftfeuchte werden aus der TRY-Datei übernommen, aber
  vom Wärmebilanzmodell aktuell nicht ausgewertet (auch das synthetische
  Klimamodell liefert dafür nur feste Platzhalterwerte) - es gibt noch
  keinen wind- oder feuchteabhängigen Lüftungswärmeverlust.
- Fehlt eine einzelne Stunde in der Datei oder ist eine Zeile nicht lesbar,
  bleibt sie auf 0 (mit Warnung) statt interpoliert zu werden - für eine
  vollständige, unbeschädigte DWD-TRY-Datei tritt das nicht auf.
- `data/TRY2026_synthetic_Testjahr.dat` ist **keine echte DWD-Datei**,
  sondern ein eigens erzeugter Testdatensatz im selben Spaltenformat (glatter
  Jahres-/Tagesgang mit Zufallsrauschen), nur zur Demonstration/zum Test des
  Imports. Für eine echte Analyse durch eine reale DWD-Testreferenzjahr-Datei
  ersetzen - dabei auf denselben Dateinamens-Konvention achten (Zeichen 4-7
  = Jahreszahl, z. B. `TRY2015_38265002_Jahr.dat`).

## Wärmebilanz für ein echtes Gebäude aus gbXML (`uGbXMLAnalysis.pas`)

Statt eines aus wenigen Kennwerten generierten Quaders kann `Analyse.lpr`
auch die reale Geometrie **und** die realen U-Werte eines Gebäudes direkt
aus einer gbXML-Datei übernehmen (z. B. Export aus DDScad MEP oder einem
anderen BIM-/CAD-Programm). Dazu `GbXML_Datei: <Pfad>` in der
Gebäudebeschreibung angeben (siehe `data/gebaeude_aus_gbxml.txt` mit der
mitgelieferten Beispieldatei `data/beispiel_reales_gebaeude.gbxml`). Ist
dieser Schlüssel gesetzt und lädt die Datei erfolgreich, werden die
geometrischen Schlüssel (`Grundflaeche`, `Laenge`/`Breite`, `Stockwerke`,
`Dachform`, `Fensteranteil`) sowie alle `Uwert_*`-Schlüssel ignoriert -
Geometrie und U-Werte kommen dann vollständig aus der Datei; ein
angegebener `Daemmstandard`/`Baujahr` wird nur noch für die grobe
Vergleichsspanne am Ende des Berichts herangezogen, sofern vorhanden.

**U-Wert-Import (`uGbXML.pas`):** Jedes `<Construction>`-Element wird
gelesen; enthält es ein `<U-value>`-Element mit einem plausiblen Wert
(> 0), wird dieser direkt übernommen. Fehlt `<U-value>` ganz - in der
Beispieldatei bei allen Fenster-/Tür-Konstruktionen der Fall -, wird
ersatzweise versucht, den Wert aus der Zahlenendung der Konstruktions-ID
abzulesen (z. B. `..._1.2` → 1,2 W/(m²K)). Diese Konvention ist nicht Teil
des gbXML-Standards, sondern eine beim Untersuchen der Beispieldatei
beobachtete Eigenheit des exportierenden Programms (bei den Bauteilen mit
explizitem `<U-value>` stimmt die ID-Endung exakt damit überein). Jede
Verwendung dieses Rückfalls wird als Warnung (`GBXML_CONSTRUCTION_UVALUE_FROM_ID`)
ausgegeben - ungeprüft übernehmen sollte man das nicht. Kann auch das nicht
aufgelöst werden, bekommt die betroffene Fläche einen neutralen
Platzhalter-U-Wert (1,0 W/(m²K) für Wände/Dach/Boden, 1,4 W/(m²K) für
transparente Öffnungen) und eine entsprechende Warnung. Die volumetrischen
Bauteilschichten (`<Layer>`/`<Material>`) selbst werden weiterhin nicht
ausgewertet - nur der fertige U-Wert.

**Einzonen-Zusammenfassung (`uGbXMLAnalysis.AggregateToSingleZone`):** Das
Projekt rechnet grundsätzlich nur mit einer einzigen thermischen Zone
(siehe oben), ein gbXML-Gebäude hat aber typischerweise mehrere Räume. Alle
Räume werden deshalb zu einer Zone zusammengefasst - aber nicht blind alle:
Räume mit einer im gbXML angegebenen `<Space><Temperature>` unterhalb von
15 °C (Standard, `DefaultUnheatedThreshold`) gelten als unbeheizt (z. B.
Keller/Flur mit Frostschutztemperatur) und werden **vollständig
ausgeschlossen** - weder ihr Volumen noch ihre Außenflächen fließen in die
Bilanz ein. Das ist eine bewusste, deutliche Vereinfachung: ein unbeheizter
Pufferraum bekäme in einem echten Mehrzonenmodell noch immer einen Teil des
Wärmestroms aus den beheizten Nachbarräumen ab, hier wird er stattdessen
komplett aus der Bilanz herausgenommen. Räume ohne angegebene Temperatur
gelten als beheizt (Default). Jeder ausgeschlossene Raum erzeugt eine
Warnung. Volumen, beheizte Geschossfläche und Luftwechselrate der neuen
Einzone sind die (volumengewichteten) Summen/Mittel über die beheizten
Räume; die pauschale Speichermasse (165.000 J/(m²K) je m² Geschossfläche,
siehe oben) wird unverändert übernommen, obwohl die Datei über
`<Layer>`/`<Material>` eigentlich genauere Werte hergäbe - auch hier bleibt
es beim groben Anhaltswert des restlichen Projekts.

**Weitere Punkte:**

- Nur Außenflächen beheizter Räume gehen in die Bilanz ein; Innenflächen
  zwischen zwei Räumen (2 Einträge in `<AdjacentSpaceId>`) werden wie schon
  beim ursprünglichen Import ausgeschlossen, ebenso Flächen mit unbekanntem
  `surfaceType`.
- `<InfiltrationFlow><BlowerDoorValue>` steht in der Beispieldatei
  durchgängig auf 0 (offenbar nicht gemessen/nicht gepflegt) und wird daher
  nicht übernommen; stattdessen gilt weiterhin der feste Standard-Luftwechsel
  aus `TRoom.Create` (0,5 1/h), volumengewichtet über die beheizten Räume
  gemittelt.
- `Surface.Name`/`Opening.Name` werden jetzt aus dem `<Name>`-Element der
  gbXML-Datei übernommen (vorher blieben sie leer) und erscheinen in der
  Flächenübersicht von `Analyse.lpr`.
- Ist kein `Daemmstandard`/`Baujahr` angegeben, entfällt die
  Vergleichsspanne im Bericht (es gibt dann keine Referenzklasse, gegen die
  verglichen werden könnte) - der Bericht weist das explizit aus, statt
  eine willkürliche Spanne anzuzeigen.

## Bekannte Vereinfachungen

- Das Testwetter (`uWeather.pas`) ist rein synthetisch (Sinuskurve), keine
  echten Messdaten - genau wie im Gespräch als Platzhalter vorgesehen.
  `Demo.lpr`/`Tests.lpr` nutzen ausschließlich dieses synthetische Wetter;
  `Analyse.lpr` kann optional echte TRY-Stundenwerte verwenden (siehe oben).
- Der Heizungsregler ist ein einfacher Zweipunktregler mit fester
  Hysterese; bei großer Heizleistung und einem 5-Minuten-Regelschritt kann
  das (wie bei realen Bang-Bang-Reglern) zu spürbaren Temperatur-Schwingungen
  führen.
- Lüftung, Sonnenstand und Bauphysik sind bewusst einfache, aber
  physikalisch plausible Modelle (Spencer-Näherung für den Sonnenstand,
  isotropes Himmelsmodell für diffuse Strahlung) - für belastbare
  Auslegungsrechnungen wären genauere Modelle (z. B. Perez-Modell) nötig.
- Auch beim gbXML-basierten Import (siehe oben) bleibt es beim
  Einzonenmodell: ein mehrstöckiges oder mehrzoniges reales Gebäude wird zu
  einer einzigen beheizten Zone zusammengefasst, unbeheizte Räume werden
  komplett ausgeschlossen statt als eigene Pufferzone mit Wärmeaustausch zu
  den beheizten Räumen modelliert.
