# Baut die Demo-, Test- und Analyseprogramme der Gebäudesimulation.
#
# Verwendung:
#   make               baut Demo, Tests und Analyse
#   make run-demo      baut und startet die Tagesgang-Demo
#   make run-tests     baut und startet die automatisierten Tests
#   make run-analyse   baut und startet die Wärmebilanz-Analyse (Beispiele in data/)
#   make clean         entfernt erzeugte Binärdateien und .o/.ppu-Dateien

FPC = fpc
FPCFLAGS = -Sc -O1 -FEsrc -FUsrc

.PHONY: all run-demo run-tests run-analyse clean

all: src/Demo src/Tests src/Analyse

src/Demo: src/Demo.lpr src/*.pas
	$(FPC) $(FPCFLAGS) src/Demo.lpr

src/Tests: src/Tests.lpr src/*.pas
	$(FPC) $(FPCFLAGS) src/Tests.lpr

src/Analyse: src/Analyse.lpr src/*.pas
	$(FPC) $(FPCFLAGS) src/Analyse.lpr

run-demo: src/Demo
	./src/Demo

run-tests: src/Tests
	./src/Tests

run-analyse: src/Analyse
	./src/Analyse

clean:
	rm -f src/*.o src/*.ppu src/Demo src/Tests src/Analyse
