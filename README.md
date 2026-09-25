# Broadside Brethren

A local **2-player split-screen co-op** naval combat game for PC (Windows / Linux / macOS),
built with **Godot 4.4 (GDScript)**. Two captains share one sea sector and one treasury.
You hunt Armada convoys, raid coastal forts, claim bounties, board crippled ships, tow
each other home and upgrade your hulls at the allied port of Haven.

The game follows the design in *AGENT DIRECTIVE: Local Co-Op Split-Screen PC Clone* (a
top-down naval combat game inspired by mobile privateer games). The name, art and audio
are original. Every ship, island and effect is drawn procedurally and every sound is
synthesized at startup, so the repository contains no binary assets.

## Running the game

1. Install [Godot 4.4+](https://godotengine.org/download) (the standard build, not .NET).
2. Open `project.godot` in the editor and press **F5**, or run it from a terminal:
   ```sh
   godot --path .
   ```
3. On the title screen choose **Set Sail**, give each captain a device, then **Begin Voyage**.

The project uses the **Compatibility (OpenGL 3.3)** renderer, so it runs on most PCs.
To ship a standalone build, add an export preset in *Project > Export* for Windows or Linux.

## Controls

Each player's actions are read only from that player's device, so input never bleeds
between viewports. Assign devices in the **Muster the Crew** screen. By default Player 1
uses keyboard + mouse, and Player 2 uses the first gamepad if one is connected,
otherwise Arrows + Numpad.

| Action | Keyboard + Mouse | Arrows + Numpad | IJKL (laptop) | Gamepad |
|---|---|---|---|---|
| Steer (1D axis) | A / D | Left / Right | J / L | Left stick / D-pad |
| Sails up / down (Reverse, Stop, Half, Full) | W / S | Up / Down | I / K | RT / LT (D-pad up/down) |
| Fire port broadside | Q | Num1 or `,` | U | LB |
| Fire starboard broadside | E | Num3 or `.` | O | RB |
| Fire bow chaser (once bought) | Space | Num0 or `/` | P | A |
| Aimed broadside toward cursor | Left click | - | - | - |
| Board / throw or cut tow-line | F | Num2 or Ctrl | H | X |
| Open Depot (docked) / use repair kit | R | Enter | Y | Y |

Global keys: **Esc / Start** pause, **F2** switch split layout, **F1 / Back** controls overlay, **F11** fullscreen.

Inside the Depot, each player navigates with their own device: sails keys move up/down,
steer keys switch tabs, fire-bow buys, and interact closes.

> Two people can share one keyboard (WASD + Arrows/Numpad), but many keyboards can't
> register lots of simultaneous key presses. Gamepads are recommended.

## Gameplay

- **Sailing:** ships carry momentum and drift. The rudder only bites with water flowing
  past it, and sails are geared rather than analog.
- **Broadsides:** each side has 2–6 cannons (by hull and upgrades) and its own reload
  timer. The guns fire one after another down the deck, 0.08 s apart. They automatically
  swing up to ±35° toward the best target in their arc, leading its motion; a reticle shows
  where. Your firing arcs are drawn only in your own viewport.
- **Pincer Barrage:** when both players hit the same ship within 3 s of each other, the
  hit deals +25% critical damage.
- **Disabling and boarding:** an enemy below 15% hull is disabled. It flees while its
  convoy still fights, otherwise it strikes its colours. Get within 12 m and board: your
  crew × upgrades, scaled by hull condition, is rolled against the enemy crew. Boarding
  together gives a bonus. A capture pays 2× gold, fills your hold with its cargo and
  gives repair kits.
- **Dismasting and towing:** at 0 hull a player is dismasted and sinks after 40 s. Your
  partner can throw a tow-line and drag you into Haven's safe zone for emergency repairs.
  You can also patch yourself with a repair kit.
- **Economy:** gold goes into one shared treasury. Cargo crates fill your own hold and
  sell automatically when you dock. Sink with cargo aboard and it's lost.
- **Haven (allied port):** a circular safe zone guarded by shore batteries. Enemies won't
  enter it or chase you into it. Slow down inside the docking ring to open the Depot:
  repairs, repair kits, upgrades and new hulls.
- **Upgrades:** Hull Strength, Cannon Count, Sail Speed, Ramming Damage, Heavy Shot, Gun
  Drills, Crew Quarters and Bow Chaser.
- **Hulls:** Sloop (fast flanker), Brigantine (balanced), Ironclad War Galley (armored
  tank that draws fire and rams hard) and Frigate (heavy broadsides).
- **Enemies:** merchant convoys with escorts on trade lanes, hunter squadrons as your
  notoriety grows, and three coastal forts that rebuild after being razed.
- **Bounties:** a chain of six named captains. The compass and screen-edge markers point
  to the current one. Defeating the last one wins the game, and endless mode continues after.

## Architecture

```text
Main (scripts/main.gd)
 |- GameManager            autoload: state machine, shared treasury, profiles, bounties
 |   `- SpawnDirector      created per voyage: convoys, hunters, bounty captains
 |- WorldViewport          hidden SubViewport (render disabled) that owns the World2D
 |   `- World              ocean, islands, Haven, forts, ships, projectiles, loot, effects
 |- DisplayLayout
 |   `- SplitScreenContainer        HSplitContainer (side-by-side) or VSplitContainer (stacked)
 |       |- SubViewportContainer_P1 -> SubViewport_P1 -> Camera2D + Player1_HUD_Canvas
 |       `- SubViewportContainer_P2 -> SubViewport_P2 -> Camera2D + Player2_HUD_Canvas
 `- Menus                  title, crew muster (device assignment), pause, help, victory
Autoloads: InputRouter (per-player devices), Sfx (split-screen-safe audio)
```

- **Shared world, two cameras.** Both player SubViewports set `world_2d` to the hidden
  WorldViewport's World2D, so the world is simulated once and drawn twice. The World
  lives in its own viewport so the split container can switch between side-by-side and
  stacked at runtime without re-parenting the simulation.
- **Private overlays.** Each SubViewport's `canvas_cull_mask` includes the shared layer
  plus that player's private layer. The aim overlay uses the private layer, so each
  player sees only their own firing arcs.
- **Isolated input.** `PlayerInput` polls one keyboard scheme or one joypad id directly
  (`Input.is_physical_key_pressed`, `Input.is_joy_button_pressed`). It doesn't use the
  shared InputMap, so inputs can't cross between players.
- **Audio (spec §9).** There are no `AudioListener2D` or `AudioStreamPlayer2D` nodes and
  both SubViewports disable their 2D listeners. `Sfx` works out which viewport rect an
  event falls in, sets volume from the distance to that player's ship, and pans by the
  event's on-screen x position. It then plays through one of seven pre-panned buses into
  a single output. All sounds are synthesized at startup.
- **Custom physics.** Ship kinematics follow the spec's pseudo-code exactly (rudder
  speed factor, keel grip, linear and angular drag). Collisions use three keel circles
  per hull against islands, which are polar-function coastlines, and against other
  ships (impulse response plus ramming damage). The tow-line is a distance constraint.
- **Ballistics.** A cannonball carries the ship's velocity plus muzzle velocity. Its
  elevation is solved from `R = v² sin 2θ / g`, and its height follows a parabola under
  g = 9.8 m/s². It hits a hull if it passes over the hull ellipse below that ship's
  freeboard. Damage = base × (1 − armor) × distance falloff.
- **Units.** Gameplay values are written in meters and converted at 8 px per meter
  (`U.M`), so the spec's 12 m boarding radius and 75 m detection radius appear verbatim.

## Spec coverage

| Spec item | Where |
|---|---|
| §2 Input action map, mixed devices, no bleeding | `scripts/core/player_input.gd`, `scripts/autoload/input_router.gd` |
| §3 Split-screen hierarchy, H/V toggle (default side-by-side HSplitContainer) | `scripts/main.gd`, `scripts/view/player_view.gd` |
| §3 Camera: lerp follow 4.0, look-ahead `v × 0.6`, speed zoom | `scripts/view/player_camera.gd` |
| §4 Ship physics model | `Ship.physics_tick()` in `scripts/ships/ship.gd` |
| §5 Broadside arcs, 0.08 s stagger, per-side reload | `scripts/ships/battery.gd` |
| §5 Parabolic ballistics and damage formula | `scripts/world/projectiles.gd`, `Ship.take_damage()` |
| §5 Boarding (< 15%, ≤ 12 m, crew contest, 2× rewards) | `PlayerShip.start_boarding()`, `World.resolve_boarding()` |
| §6 Shared treasury, floating crates with bob | `scripts/autoload/game_manager.gd`, `scripts/world/loot.gd` |
| §6 Pincer Barrage, towing, threat-based aggro | `Ship.take_damage()`, `World._tow_constraints()`, `EnemyShip._pick_target()` |
| §7 AI FSM (PATROL / ALERT / BROADSIDE_ENGAGE / FLEE / SURRENDER) | `scripts/ships/enemy_ship.gd` |
| Step 5 Port safe zone, docking, upgrade shop | `scripts/world/port.gd`, `scripts/ui/shop_panel.gd` |
| Step 6 Compasses to teammate and bounty, per-view HUD | `scripts/ui/hud.gd` |
| §9 Single unified listener with viewport-based panning | `scripts/autoload/sfx.gd` |

"Horizontal split" is read as the spec's `HSplitContainer`, which puts the players side
by side. That suits 16:9 monitors in a top-down game with 360° movement. The stacked
layout (`VSplitContainer`) is one keypress away (F2), or can be chosen in the lobby.

## Automated smoke test

`scripts/tests/autotest.gd` starts a two-player voyage with bot-controlled captains. It
checks docking, the Depot, the layout toggle, pausing, combat, dismasting and the
tow-line, then prints a pass/fail summary.

```sh
# Logic only (no window), deterministic 60 fps:
godot --headless --path . --fixed-fps 60 -- --autotest --duration=60
# With rendering + screenshots:
godot --path . -- --autotest --duration=40 --shots=res://screenshots
```

## Project layout

```text
scripts/
  autoload/   game_manager.gd  input_router.gd  sfx.gd
  core/       u.gd (constants)  ship_db.gd (hulls, upgrades, enemies, bounties)  player_input.gd
  ships/      ship.gd  player_ship.gd  enemy_ship.gd  battery.gd
  world/      world.gd  spawn_director.gd  island.gd  port.gd  fort.gd
              projectiles.gd  loot.gd  effects.gd  wakes.gd  ocean.gd  ocean.gdshader
  view/       player_view.gd  player_camera.gd  aim_overlay.gd
  ui/         hud.gd  shop_panel.gd  menus.gd
  tests/      autotest.gd
```
