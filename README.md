# Operation: Iron Grid

**Operation: Iron Grid** is a dieselpunk isometric turn-based tactical strategy game built in **Godot 4**. Inspired by the heavy mechanical atmosphere of *Ring of Red*, *Steel Battalion*, and *MechWarrior*, the grid-based tactical maneuvering of *Advance Wars* and *Fire Emblem*, and the directional card-flipping showdowns of *Final Fantasy VIII*'s *Triple Triad*.

![Isometric Battlefield & Tactical HUD](screenshot_gameplay.png)

*Tactical battlefield view: extruded 2.5D isometric terrain, movement range highlights, Dijkstra fuel path planning, and real-time telemetry HUD.*

![FF6-style Battle Screen](screenshot_battle.png)

*Battle screen: pixel-art walkers with articulated legs, a terrain backdrop chosen by the defender's tile, attack banners and the CRT command HUD.*

![Main Menu & AFW Codex](screenshot_main_menu.png)

*Command HQ briefing console: 3 selectable battle theaters, satellite reconnaissance preview, and interactive Armored Walker Hangar Codex.*

---

## Core Gameplay & Turn Loop

Players command the **8th Iron Division** against the **Kriegs-Syndikat Red** across an extruded 2.5D isometric battlefield divided into square tactical nodes with varying terrain types and elevations (`0m` to `400m`).

Each turn cycles through three phases:

1. **Player Command Phase**:
   - Select any friendly Armored Fighting Walker (AFW) to compute reachable movement nodes within its current **Diesel Fuel** budget (using Dijkstra pathfinding across terrain and elevation climbs).
   - Hover over reachable enemy nodes to inspect a real-time **Skirmish Engagement Forecast** detailing approach vectors, terrain/elevation modifiers, projected card control, and estimated hull damage.
   - Move to secure strategic **Objective Cities**, press **`R`** (`WAIT / REFUEL`) to entrench (`+15% DEF` and `+5 Fuel`), or move directly onto an enemy-occupied node to trigger a collision engagement.
2. **Skirmish Resolution Phase (Automated Showdown)**:
   - When two opposing walkers occupy the same node, the game launches the **Automated Skirmish Resolver**.
   - Combines a **Stats-vs-Stats** exchange (`Firepower` vs `Armor Rating`, scaled by approach terrain and high-ground elevation) with a **3-Bout Equipment Deck Clash** on a **3x3 Triple Triad Matrix**.
   - Each walker deploys its 3 equipped weapon/armor/tactical cards onto the 3x3 board. Directional power ranks (`N, E, S, W` from `1–9` and `A`) are compared against adjacent opposing cards:
     - **Overmatch Capture**: Higher directional ranks flip adjacent enemy cards to the attacker's faction.
     - **Tactical Plus Overload**: Matching edge sums across two or more adjacent sides trigger a combo flip.
   - Controlled cards add their `Damage` and `Shield` ratings to the final hull exchange. If both units survive, the loser of the clash is dislodged and pushed back to an adjacent retreat tile.
   - **Battle screen.** Each skirmish plays out on a side-view, FF6-style pixel-art battle screen. The game cuts from the grid to the two walkers facing off in front of a backdrop chosen by the defender's terrain, then cuts back.
     - The approach direction decides which side each walker stands on, and the higher walker is drawn raised.
     - The six card plays run in order. Each shows a banner with the card name, then its own animation:
       - **Weapons:** the card's attack animation.
       - **Armor and tactical cards:** the card's effect, then a quick follow-up shot.
     - Bouncing damage numbers match the resolver exactly.
     - Captured cards are reported as text, e.g. `OVERMATCH: 1 SYSTEM CAPTURED`. The 3×3 board itself isn't drawn.
     - Commands are chosen automatically for now; interactive commands are a planned follow-up.
3. **Syndicate AI Phase**:
   - Enemy walkers evaluate reachable tiles, approach vectors, high-ground advantages, fuel reserves, and objective priorities tailored to the map's strategic profile (`Pitched Battle`, `Fortified Defense`, or `Blitzkrieg Offense`).

### Victory Conditions
- **Annihilation** of either side ends the mission immediately.
- **Objective victories** (holding every bridgehead, holding a Syndicate HQ bunker, or the Syndicate overrunning every Citadel node) are confirmed at the **end of a full turn**, so a capture has to survive the enemy's response phase.
- When the **turn limit** expires, the mission is scored by its strategic profile (bridgehead majority, Citadel held, or HQ not taken).

---

## Terrain & Elevation Matrix

| Terrain Type | Code | Base Fuel | Attack Mod | Defense Mod | Card Edge Bonus | Tactical Notes |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **Transit Road** | `ROD` | `1` | `+5%` | `0%` | `+0` | Fastest transit artery for heavy dreadnoughts |
| **Open Plain** | `PLN` | `2` | `0%` | `+5%` | `+0` | Standard open maneuvering ground |
| **Fortified City** | `CTY` | `2` | `+10%` | `+25%` | `+1` | Repairs **+12 Armor** & restores **+4 Fuel** at turn start |
| **Trench Timber** | `TRN` | `3` | `+5%` | `+15%` | `+0` | Prepared defensive cover and ambush concealment |
| **River Ford** | `RIV` | `4` | `-15%` | `-15%` | `-1` | Bogged down & exposed (`Falke` amphibious gear reduces cost) |
| **Mountain Crag** | `MTN` | `5` | `+15%` | `+30%` | `+1` | Commanding rock bastion (`Donner` quad legs reduce climb cost) |

### Elevation (`0m` – `400m`)
- **Climbing Fuel Surcharge**: Moving uphill costs `+1 Fuel` per `100m` elevation level gained.
- **High Ground Plunging Fire**: Attacking from higher elevation down onto a defender grants **+12% Firepower**, **+10% Armor deflection**, and **+1 to all Card Directional Ranks** per elevation level differential.
- **Uphill Assault Penalty**: Attacking uphill suffers **-10% Firepower** and **-1 to Card Directional Ranks** per level.

---

## Armored Fighting Walkers (6 Chassis Types)

1. **KPZ-09 "Sturmjäger" (`VANGUARD` — Medium Assault Walker)**
   - **Stats**: `110 Hull` | `30 Armor Rating` | `34 Firepower` | `13 Fuel` (`+5/turn`)
   - **Deck**: *88mm KwK AP-Shell*, *Sloped Krupp Plate*, *Twin MG-42 Salvo*
2. **VK-100 "Siegebreaker" (`GOLIATH` — Super-Heavy Dreadnought)**
   - **Stats**: `155 Hull` | `44 Armor Rating` | `46 Firepower` | `10 Fuel` (`+4/turn`, `+1` off-road fuel surcharge)
   - **Deck**: *210mm Siege Howitzer*, *Ferro-Bunker Bulkhead*, *Quad Flak-38 Battery*
3. **Sd.Kfz-22 "Spähfalke" (`FALKE` — Light Recon Strider)**
   - **Stats**: `85 Hull` | `21 Armor Rating` | `28 Firepower` | `17 Fuel` (`+6/turn`, Amphibious Seals & `-1` off-road fuel reduction)
   - **Deck**: *50mm Rapid Autocannon*, *Gyro-Flank Thrusters*, *Optical Rangefinder*
4. **SPG-88 "Spinne" (`DONNER` — Quadruped Mountain Walker)**
   - **Stats**: `98 Hull` | `26 Armor Rating` | `43 Firepower` | `12 Fuel` (`+5/turn`, Mountain Climbing Gear)
   - **Deck**: *Nebelwerfer Rocket Pod*, *Elevation Ballistics*, *Quad Anchor Struts*
5. **Befehls-IV "Kaiserstuhl" (`KOMMANDANT` — Tactical Command Walker)**
   - **Stats**: `120 Hull` | `34 Armor Rating` | `36 Firepower` | `14 Fuel` (`+5/turn`)
   - **Deck**: *Enigma ECM Scrambler*, *Command Uplink*, *105mm StuH Howitzer*
6. **Sturm-V "Brenner" (`MOLOCH` — Heavy Urban Brawler)**
   - **Stats**: `135 Hull` | `38 Armor Rating` | `41 Firepower` | `12 Fuel` (`+5/turn`)
   - **Deck**: *Thermite Flame Lance*, *Hydraulic Pile-Bunker*, *Reactive Shield Wall*

---

## Battle Arenas (3 Maps)

1. **Operation: Iron Bridge (`PITCHED BATTLE`)**
   - Symmetrical meeting engagement across the Rhine-Fulda river valley (`0m`) spanned by two transit road bridges (`100m`), four bridgehead cities (`200m`), and flanking mountain ridges (`300m`).
2. **Bastion Redoubt (`FORTIFIED DEFENSE`)**
   - Asymmetric defense of Citadel Höhenburg (`300m–400m`) against a numerically superior 5-walker Syndicate assault column advancing up the western valley roads.
3. **Breakthrough at Kessel-9 (`BLITZKRIEG OFFENSE`)**
   - Asymmetric offensive leading a 5-walker mobile spearhead to breach entrenched Syndicate gate guards and capture and hold the Eastern HQ Bunker within 10 turns.

---

## Controls

| Input | Action |
| :--- | :--- |
| **Left Mouse Click** | Select walker / Move to highlighted tile / Engage enemy node |
| **Right / Middle Mouse Drag** | Pan tactical camera |
| **WASD / Arrow Keys** | Pan tactical camera |
| **Mouse Wheel Up / Down** | Zoom camera in / out |
| **`R`** | Wait, Entrench (`+15% DEF`), & Refuel (`+5 Fuel`) selected walker |
| **`E`** | End Player Command Phase |
| **`C`** | Reset & center camera on battlefield |
| **`H`** | Toggle Tactical Field Manual & Terrain Chart |
| **`Space` / `Enter` / Left Click** | Battle screen: skip to the result / confirm the result |
| **`S`** | Battle screen: toggle 1× / 2× playback speed |
| **`Esc`** | Deselect unit / Close modal |

---

## Architecture & Project Structure

```text
iron-grid/
├── project.godot                   # Godot 4.7 project configuration & autoloads
├── icon.svg                        # Custom vector project icon
├── screenshot_main_menu.png        # Command HQ briefing & codex screenshot
├── screenshot_gameplay.png         # Tactical isometric battlefield screenshot
├── autoload/
│   ├── GlobalState.gd              # Global turn/phase state, card/mech/map catalogs, combat log
│   └── SoundManager.gd             # Procedural retro/dieselpunk WAV audio synthesizer
├── assets/battle/                  # Generated pixel art (do not hand-edit; see Battle Art Pipeline)
│   ├── mechs/                      # <chassis>[_variant]_<faction>.png pose sheets + <chassis>.json anchors
│   ├── backdrops/                  # 360x152 terrain backdrops (plain, road, river, forest, city, mountain)
│   ├── fx/                         # Slab, radio mast & rangefinder attachments per faction
│   └── font/                       # 5x7 bitmap font
├── tools/battle_sprites/           # Stdlib-only Python generator for everything in assets/battle
├── scenes/
│   ├── MainMenu.tscn               # Command HQ briefing console, 3-map selector & Mech Hangar Codex
│   ├── Battlefield.tscn            # Root battle scene (GridMap, UnitContainer, Camera2D, UIOverlay)
│   └── dev/BattlePreview.tscn      # Dev-only battle screen preview (every chassis, card, terrain)
└── scripts/
    ├── data/
    │   ├── EquipmentCard.gd        # Triple Triad directional ranks & damage/shield card struct
    │   ├── GridTileData.gd         # Terrain type, elevation, fuel cost & combat modifier struct
    │   ├── MapDefinition.gd        # Arena layout, strategy mode, objectives & unit spawns
    │   └── MechData.gd             # Core walker struct (armor, firepower, fuel, mobility, deck)
    ├── battle/
    │   ├── Battlefield.gd          # Turn flow controller (Player -> Skirmish Resolution -> AI)
    │   ├── IsoGridMap.gd           # 2.5D isometric terrain renderer & Dijkstra fuel pathfinder
    │   ├── UnitContainer.gd        # Y-sorted mech manager, collision checks & knockback logic
    │   ├── MechUnit.gd             # Procedural multi-part isometric mech renderer & animator
    │   ├── SkirmishEngine.gd       # Stats-vs-Stats + 3x3 Triple Triad card clash resolver
    │   └── AIController.gd         # Utility-based tactical AI decision engine
    ├── battle_screen/
    │   ├── BattleScreen.gd         # FF6-style resolution screen (SubViewport 360x225, scaled 4x)
    │   ├── BattleStage.gd          # Phase machine + drawing: intro, 6 card beats, ending, result
    │   ├── BattleTimeline.gd       # SkirmishResult -> presentation beats (no rule changes)
    │   ├── WeaponAnims.gd          # Per-weapon attack animations
    │   ├── SupportAnims.gd         # Armor/tactical effects, softened hits, attachments
    │   ├── BattleFX.gd             # Pixel effect primitives (flashes, tracers, explosions, panels)
    │   ├── BattleLayout.gd         # Side/elevation placement & terrain -> backdrop
    │   ├── MechSpriteBank.gd       # Sprite sheet + anchor metadata loader
    │   ├── PixelFont.gd            # 5x7 bitmap text & wrapping
    │   └── BattlePreview.gd        # Dev preview controller
    └── ui/
        ├── MainMenu.gd             # War-room menu & interactive Mech Hangar Codex
        └── UIOverlay.gd            # In-game CRT telemetry HUD, terrain inspector & forecast
└── tests/
    ├── Playtest.tscn               # Headless automated playtest entry scene
    ├── playtest.gd                 # Rule checks + full-mission playthroughs with per-frame invariants
    ├── BattleScreenTests.tscn      # Battle screen unit tests (timeline, layout, anims, screen contract)
    └── run_battle_tests.sh         # Headless runner for the battle screen tests
```

---

## Running the Game

1. Open **Godot Engine 4.x** (tested with Godot `4.7-stable`).
2. Import `project.godot` and press **F5** (or run from the command line):

```powershell
godot --path .
```

---

## Automated Playtest

`tests/Playtest.tscn` checks the core rules (fuel costs, optimal pathfinding, skirmish forecasts, card placement, elevation modifiers, and victory conditions). It then plays complete missions on every map with greedy, turtle, and seeded-random commanders. Every frame it asserts game-state invariants: no stacked walkers, fuel and armor in range, sprites matching their grid tiles, and nothing advancing after game over.

```bash
godot --headless --path . res://tests/Playtest.tscn          # exit code = number of failures
PLAYTEST_POLICIES=greedy PLAYTEST_VERBOSE=1 godot --headless --path . res://tests/Playtest.tscn
```

```powershell
# Windows PowerShell equivalent of the environment-variable form
$env:PLAYTEST_POLICIES = 'greedy'; $env:PLAYTEST_VERBOSE = '1'; godot --headless --path . res://tests/Playtest.tscn
Remove-Item Env:PLAYTEST_POLICIES, Env:PLAYTEST_VERBOSE
```

## Battle Art Pipeline

All battle screen art is generated pixel art. `tools/battle_sprites/generate.py` builds every chassis from shaded parts. The legs are a two-bone hip→knee→ankle IK rig, re-solved for every pose so the feet stay planted.

The generator renders each pose and writes palette-swapped sheets for the Coalition and Syndikat factions. It also writes the backdrops, attachments and font. It uses only the Python standard library, and its output is deterministic.

```bash
python3 tools/battle_sprites/generate.py           # regenerate assets/battle
python3 tools/battle_sprites/generate.py --check   # exit 1 if committed art differs from the generator
python3 -m unittest discover -s tools/battle_sprites
tests/run_battle_tests.sh                          # battle screen unit tests (headless)
godot --path . res://scenes/dev/BattlePreview.tscn # browse chassis, cards, terrains and endings
```

On Windows, run the same commands in PowerShell (5.1 or 7+):

```powershell
py -3 tools\battle_sprites\generate.py
py -3 tools\battle_sprites\generate.py --check
py -3 -m unittest discover -s tools\battle_sprites
.\tests\run_battle_tests.ps1                       # or: .\tests\run_battle_tests.ps1 -Godot C:\path\to\Godot_v4.7-stable_win64_console.exe
godot --path . res://scenes/dev/BattlePreview.tscn
```

Some notes for Windows:

- **Use the console build of Godot.** The test runner reads Godot's output. On Windows that only works with the `*_console.exe` build, which the runner finds on `PATH` or through `$env:GODOT`.
- **If scripts are blocked, unblock them.** PowerShell may refuse to run local scripts. Allow them once with `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- **Line endings are handled.** The generator writes the same bytes on every OS, and `.gitattributes` keeps the generated JSON as LF, so `--check` passes on Windows too.

After regenerating, run `godot --headless --path . --import` so Godot picks up the new PNGs.

## Balance Experiments

`tests/Balance.tscn` plays full missions with switchable entrenchment and City-healing rules (`scripts/battle/BalanceProbe.gd`; the defaults match the shipped rules) and prints one JSON line per mission. `tests/TacticalBot.gd` is a competent Coalition commander that mirrors the Syndicate AI's scoring; `tactical:N` adds seeded variety by picking among near-best moves.

```bash
BALANCE_VARIANT=full BALANCE_POLICIES=$(python3 -c "print(','.join(f'tactical:{i}' for i in range(1,41)))") \
  BALANCE_MAPS=0,1,2 godot --headless --path . res://tests/Balance.tscn > out_full.log
python3 tests/analyze_balance.py out_*.log         # win rates, outcome flips vs full, healing, fight counterfactuals
godot --headless --path . -s tests/matrix.gd       # every chassis vs every chassis, no fight selection
godot --headless --path . -s tests/backfire.gd     # setups where entrenching hurts the defender
```
