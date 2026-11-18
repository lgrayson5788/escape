with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Numerics.Discrete_Random;
with ECS;
with Game_Components;  use Game_Components;
with Game_ECS;         use Game_ECS;

procedure Main is

   use type ECS.Entity;

   Width  : constant := 20;
   Height : constant := 10;

   --  Random behavior for entities
   subtype Row_Index is Natural range 0 .. Height - 1;
   package Row_Random is new Ada.Numerics.Discrete_Random (Row_Index);
   Gen : Row_Random.Generator;

   Player_Mask : constant World.Signature :=
     World.Mask_Of (Position, Velocity, Health);
   Mover_Mask  : constant World.Signature :=
     World.Mask_Of (Position, Velocity);

   Player : Entity := No_Entity;
   Turn   : Natural := 0;
   Score  : Natural := 0;
   Alive  : Boolean := True;
   Ok     : Boolean;

   procedure Spawn_Obstacle (X, Y : Float);
   procedure Spawn_Enemy (X, Y, DX, DY : Float);
   function Get_Player_HP return Natural;
   function Get_Position (Target : Entity) return Position_Data;
   function Get_Velocity (Target : Entity) return Velocity_Data;
   procedure Render;
   procedure Read_Input;
   procedure Update_Movement;
   procedure Update_Collisions;

   procedure Spawn_Obstacle (X, Y : Float) is
      E : constant Entity := World.Create;
   begin
      if E /= No_Entity then
         Positions.Set (E, (X => X, Y => Y), Ok);
      end if;
   end Spawn_Obstacle;

   procedure Spawn_Enemy (X, Y, DX, DY : Float) is
      E : constant Entity := World.Create;
   begin
      if E /= No_Entity then
         Positions.Set (E, (X => X, Y => Y), Ok);
         if Ok then
            Velocities.Set (E, (DX => DX, DY => DY), Ok);
         end if;
      end if;
   end Spawn_Enemy;

   function Get_Player_HP return Natural is
   begin
      for I in 1 .. Healths.Count loop
         if Healths.Owner (I) = Player then
            return Healths.Value (I).Points;
         end if;
      end loop;
      return 0;
   end Get_Player_HP;

   function Get_Position (Target : Entity) return Position_Data is
   begin
      for I in 1 .. Positions.Count loop
         if Positions.Owner (I) = Target then
            return Positions.Value (I);
         end if;
      end loop;
      return (X => 0.0, Y => 0.0);
   end Get_Position;

   function Get_Velocity (Target : Entity) return Velocity_Data is
   begin
      for I in 1 .. Velocities.Count loop
         if Velocities.Owner (I) = Target then
            return Velocities.Value (I);
         end if;
      end loop;
      return (DX => 0.0, DY => 0.0);
   end Get_Velocity;

   procedure Render is
      Grid : array (0 .. Height - 1, 0 .. Width - 1) of Character :=
        [others => [others => ' ']];
      P_HP : constant Natural := Get_Player_HP;
   begin
      for I in 1 .. Positions.Count loop
         declare
            E   : constant Entity := Positions.Owner (I);
            Pos : constant Position_Data := Positions.Value (I);
            GX  : constant Integer := Integer (Float'Rounding (Pos.X));
            GY  : constant Integer := Integer (Float'Rounding (Pos.Y));
         begin
            if GX in 0 .. Width - 1 and then GY in 0 .. Height - 1 then
               if World.Matches (E, Player_Mask) then
                  Grid (GY, GX) := '@';
               elsif World.Matches (E, Mover_Mask) then
                  declare
                     Vel : constant Velocity_Data := Get_Velocity (E);
                  begin
                     if Vel.DY > 0.0 then
                        Grid (GY, GX) := 'V';
                     elsif Vel.DY < 0.0 then
                        Grid (GY, GX) := '^';
                     elsif Vel.DX > 0.0 then
                        Grid (GY, GX) := '>';
                     elsif Vel.DX < 0.0 then
                        Grid (GY, GX) := '<';
                     else
                        Grid (GY, GX) := '#';
                     end if;
                  end;
               else
                  Grid (GY, GX) := '#';
               end if;
            end if;
         end;
      end loop;

      New_Line;
      Put_Line ("Backend: " & Backend);
      Put_Line ("Turn:" & Turn'Image
                & " | HP:" & P_HP'Image
                & " | Score:" & Score'Image
                & " | Entities:" & World.Live_Count'Image);
      Put_Line ("+" & [1 .. Width => '-'] & "+");
      for Y in 0 .. Height - 1 loop
         Put ('|');
         for X in 0 .. Width - 1 loop
            Put (Grid (Y, X));
         end loop;
         Put_Line ("|");
      end loop;
      Put_Line ("+" & [1 .. Width => '-'] & "+");
   end Render;

   procedure Read_Input is
      Key : Character;  -- single char to read end user key press
      Vel  : Velocity_Data := (DX => 0.0, DY => 0.0);
   begin
      Put ("Move [w/a/s/d, q=quit]: ");
      loop
         Get_Immediate (Key); -- Reads a single key press, prevents the need of hitting enter
         case Key is
               when 'w' | 'W' => Vel.DY := -1.0;
               when 's' | 'S' => Vel.DY :=  1.0;
               when 'a' | 'A' => Vel.DX := -1.0;
               when 'd' | 'D' => Vel.DX :=  1.0;
               when 'q' | 'Q' => Alive  := False;
               when others    => null;
         end case;
         exit when Key in 'w' | 'W' | 's' | 'S' -- leave loop if the key is valid
                        | 'a' | 'A' | 'd' | 'D' | 'q' | 'Q';
      end loop;
      Velocities.Set (Player, Vel, Ok);
   end Read_Input;

   procedure Update_Movement is
   begin
      for I in reverse 1 .. Velocities.Count loop
         declare
            E : constant Entity := Velocities.Owner (I);
         begin
            if World.Matches (E, Mover_Mask) then
               declare
                  V : constant Velocity_Data := Velocities.Value (I);
                  P : Position_Data := Get_Position (E);
               begin
                  P.X := P.X + V.DX;
                  P.Y := P.Y + V.DY;

                  if E = Player then
                     P.X := Float'Max (0.0, Float'Min (Float (Width - 1), P.X));
                     P.Y := Float'Max (0.0, Float'Min (Float (Height - 1), P.Y));
                     Positions.Set (E, P, Ok);
                  elsif P.X < 0.0 or else P.X >= Float (Width)
                    or else P.Y < 0.0 or else P.Y >= Float (Height)
                  then
                     World.Destroy (E);
                     Score := Score + 10;
                  else
                     Positions.Set (E, P, Ok);
                  end if;
               end;
            end if;
         end;
      end loop;
   end Update_Movement;

   procedure Update_Collisions is
      P_Pos : constant Position_Data := Get_Position (Player);
      PX    : constant Integer := Integer (Float'Rounding (P_Pos.X));
      PY    : constant Integer := Integer (Float'Rounding (P_Pos.Y));
   begin
      for I in reverse 1 .. Positions.Count loop
         declare
            E : constant Entity := Positions.Owner (I);
         begin
            if E /= Player then
               declare
                  Pos : constant Position_Data := Positions.Value (I);
                  EX  : constant Integer := Integer (Float'Rounding (Pos.X));
                  EY  : constant Integer := Integer (Float'Rounding (Pos.Y));
               begin
                  if EX = PX and then EY = PY then
                     declare
                        New_HP : Natural := Get_Player_HP;
                     begin
                        if New_HP > 0 then
                           New_HP := New_HP - 1;
                           Healths.Set (Player, (Points => New_HP), Ok);
                        end if;
                        if New_HP = 0 then
                           Alive := False;
                        end if;
                     end;

                     --  Enemies vanish on impact; static obstacles stay.
                     if World.Matches (E, Mover_Mask) then
                        World.Destroy (E);
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;
   end Update_Collisions;

begin
   --  Seed Random
   Row_Random.Reset (Gen);

   --  Initial spawns for game
   Player := World.Create;
   Positions.Set  (Player, (X => 2.0, Y => 5.0), Ok);
   pragma Assert (Ok);
   Velocities.Set (Player, (DX => 0.0, DY => 0.0), Ok);
   pragma Assert (Ok);
   Healths.Set    (Player, (Points => 3), Ok);
   pragma Assert (Ok);

   Spawn_Obstacle (6.0, 2.0);
   Spawn_Obstacle (11.0, 7.0);
   Spawn_Obstacle (15.0, 4.0);
   Spawn_Obstacle (15.0, 9.0);

   --  Game loop
   while Alive loop
      Render;
      Read_Input;
      exit when not Alive;

      Turn := Turn + 1;
      Update_Movement;
      Update_Collisions;

      if Turn mod 2 = 0 then
         Spawn_Enemy
           (X  => Float (Width - 1),
            Y  => Float (Row_Random.Random (Gen) mod Height),
            DX => -1.0,
            DY => 0.0);
         Spawn_Enemy
         (X  => Float (Row_Random.Random (Gen) mod Width),
            Y  => Float (0),
            DX => 0.0,
            DY => 1.0);
      end if;
   end loop;

   Render;
   Put_Line ("GAME OVER! Final Score:" & Score'Image);
end Main;