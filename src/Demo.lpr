{ ============================================================================
  Demo.lpr

  Das durchgängige Beispielgebäude aus dem Entwurfsgespräch: ein Haus mit
  Wohnzimmer und Flur, einer gemeinsamen Innenwand, einer Südwand mit
  Fenster, Heizungsregler und solarem Gewinn durch das Fenster. Simuliert
  wird ein Tagesgang (24 Stunden, 5-Minuten-Schritte) mit synthetischem
  Testwetter.
  ============================================================================ }
program Demo;

{$mode objfpc}{$H+}

uses
  SysUtils, DateUtils,
  uGeometry,
  uConstruction,
  uBuilding,
  uRCModel,
  uRCBuilder,
  uSolar,
  uSimulation;

var
  Building: TBuilding;

  LivingRoom, Hall: TRoom;

  Brick, Insulation, Plaster, Glass: TMaterial;

  ExteriorWall, InternalWall: TConstruction;

  SouthWall, InnerWall, Window: TSurface;

  Builder: TRCModelBuilder;
  Model: TRCModel;
  Simulation: TRCSimulation;

  LivingNode: TRCNode;

  StartTime, CurrentTime: TDateTime;
  I: Integer;

begin
  Building := TBuilding.Create;
  try
    Building.Name := 'Testgebäude';

    { ==========================================================
      MATERIALIEN
      ========================================================== }

    Brick := TMaterial.Create;
    Brick.Name := 'Ziegel';
    Brick.Lambda := 0.60;
    Brick.Density := 1800;
    Brick.HeatCapacity := 840;

    Insulation := TMaterial.Create;
    Insulation.Name := 'Mineralwolle';
    Insulation.Lambda := 0.035;
    Insulation.Density := 40;
    Insulation.HeatCapacity := 840;

    Plaster := TMaterial.Create;
    Plaster.Name := 'Putz';
    Plaster.Lambda := 0.70;
    Plaster.Density := 1600;
    Plaster.HeatCapacity := 840;

    Glass := TMaterial.Create;
    Glass.Name := 'Fensterglas';
    Glass.Lambda := 1.0;
    Glass.Density := 2500;
    Glass.HeatCapacity := 750;

    { ==========================================================
      AUSSENWAND (Putz / Ziegel / Dämmung / Putz)
      ========================================================== }

    ExteriorWall := TConstruction.Create;
    ExteriorWall.Name := 'Außenwand';
    ExteriorWall.AddLayer(Plaster, 0.015);
    ExteriorWall.AddLayer(Brick, 0.115);
    ExteriorWall.AddLayer(Insulation, 0.160);
    ExteriorWall.AddLayer(Plaster, 0.015);

    { ==========================================================
      INNENWAND
      ========================================================== }

    InternalWall := TConstruction.Create;
    InternalWall.Name := 'Innenwand';
    InternalWall.AddLayer(Plaster, 0.015);
    InternalWall.AddLayer(Brick, 0.115);
    InternalWall.AddLayer(Plaster, 0.015);

    { ==========================================================
      RÄUME
      ========================================================== }

    LivingRoom := TRoom.Create;
    LivingRoom.ID := 'living';
    LivingRoom.Name := 'Wohnzimmer';
    LivingRoom.Volume := 5.0 * 5.0 * 2.8;  // 70 m³
    LivingRoom.AirChangeRate := 0.5;

    Hall := TRoom.Create;
    Hall.ID := 'hall';
    Hall.Name := 'Flur';
    Hall.Volume := 75.0;
    Hall.AirChangeRate := 0.5;

    Building.AddRoom(LivingRoom);
    Building.AddRoom(Hall);

    { ==========================================================
      GEMEINSAME INNENWAND (Wohnzimmer / Flur)
      ========================================================== }

    InnerWall := TSurface.Create;
    InnerWall.ID := 'wall_living_hall';
    InnerWall.Name := 'Wand Wohnzimmer / Flur';
    InnerWall.Kind := skWall;
    InnerWall.Area := 25.0;
    InnerWall.IsExterior := False;
    InnerWall.Construction := InternalWall;

    InnerWall.SideA.Space := LivingRoom;
    InnerWall.SideA.Name := 'Wohnzimmer';

    InnerWall.SideB := TSurfaceSide.Create;
    InnerWall.SideB.Space := Hall;
    InnerWall.SideB.Name := 'Flur';

    Building.AddSurface(InnerWall);

    { ==========================================================
      SÜDWAND (5 m x 2,8 m), geometrisch über ein Polygon beschrieben
      ========================================================== }

    SouthWall := TSurface.Create;
    SouthWall.ID := 'wall_south';
    SouthWall.Name := 'Südwand Wohnzimmer';
    SouthWall.Kind := skExteriorWall;
    SouthWall.IsExterior := True;
    SouthWall.Construction := ExteriorWall;
    SouthWall.SideA.Space := LivingRoom;

    { Y = 0 ist die Südseite; die Punkte werden geometrisch aus Breite und
      Höhe abgeleitet, statt Fläche/Ausrichtung von Hand zu setzen. }
    SouthWall.Polygon.AddPoint(Point3D(0, 0, 0));
    SouthWall.Polygon.AddPoint(Point3D(5, 0, 0));
    SouthWall.Polygon.AddPoint(Point3D(5, 0, 2.8));
    SouthWall.Polygon.AddPoint(Point3D(0, 0, 2.8));
    SouthWall.UpdateGeometry;  // -> Area = 14 m², Orientation = 180° (Süd), Tilt = 90°

    Building.AddSurface(SouthWall);

    { ==========================================================
      FENSTER (1,5 m x 1,5 m), Teil der Südwand
      ========================================================== }

    Window := TSurface.Create;
    Window.ID := 'window_south';
    Window.Name := 'Fenster Süd';
    Window.Kind := skWindow;
    Window.IsExterior := True;
    Window.IsTransparent := True;
    Window.SideA.Space := LivingRoom;

    Window.UValue := 0.8;          // W/(m²K), Dreifachverglasung
    Window.SolarGValue := 0.55;    // g-Wert
    Window.ShadingFactor := 1.0;

    Window.Polygon.AddPoint(Point3D(1.75, 0, 0.8));
    Window.Polygon.AddPoint(Point3D(3.25, 0, 0.8));
    Window.Polygon.AddPoint(Point3D(3.25, 0, 2.3));
    Window.Polygon.AddPoint(Point3D(1.75, 0, 2.3));
    Window.UpdateGeometry;  // -> Area = 2,25 m²

    { Das Fenster ist geometrisch Teil der Südwand (reduziert deren
      Nettofläche), wird aber als eigene, parallele Fläche im Gebäude
      geführt, damit der RC-Builder für Wand und Fenster getrennte
      (parallele) Widerstandspfade Raum<->Außenluft erzeugt. }
    SouthWall.AddOpening(Window);
    Building.AddSurface(Window);

    WriteLn(Format('Südwand: Bruttofläche %.2f m², Nettofläche %.2f m² (Fenster %.2f m²)',
      [SouthWall.Area, SouthWall.NetArea, Window.Area]));
    WriteLn(Format('Südwand-Ausrichtung: %.1f° (180° = Süd), Neigung: %.1f°',
      [SouthWall.Orientation, SouthWall.Tilt]));
    WriteLn;

    { ==========================================================
      RC-MODELL ERZEUGEN
      ========================================================== }

    Builder := TRCModelBuilder.Create;
    Model := Builder.Build(Building);
    Builder.Free;

    { ==========================================================
      SIMULATION: 24 Stunden, 5-Minuten-Schritte, synthetisches Wetter
      ========================================================== }

    Simulation := TRCSimulation.Create(Building, Model, 'living');
    try
      Simulation.Heating.Setpoint := 21.0;
      Simulation.Heating.DeadBand := 0.5;
      Simulation.Heating.MaxPower := 5000;

      LivingNode := Model.FindNode('room_living');

      StartTime := EncodeDateTime(2026, 8, 14, 0, 0, 0, 0);

      WriteLn('Zeit   Außen [C]  Sonne [W]  Wohnzimmer [C]  Heizung');
      WriteLn('----------------------------------------------------');

      for I := 0 to 287 do
      begin
        CurrentTime := StartTime + I * (5.0 / 1440.0);

        Simulation.Step(CurrentTime);

        if (I mod 12) = 0 then
        begin
          WriteLn(Format('%s   %6.1f    %7.0f      %6.2f          %s',
            [
              FormatDateTime('hh:nn', CurrentTime),
              Simulation.OutsideTemperature,
              Simulation.LastWeather.DirectNormalIrradiance,
              LivingNode.Temperature,
              BoolToStr(Simulation.Heating.HeatingOn, True)
            ]));
        end;
      end;

    finally
      Simulation.Free;
    end;

    Model.Free;

  finally
    Building.Free;

    Brick.Free;
    Insulation.Free;
    Plaster.Free;
    Glass.Free;

    ExteriorWall.Free;
    InternalWall.Free;
  end;
end.
