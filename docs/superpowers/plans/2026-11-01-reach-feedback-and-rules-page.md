# Out-of-Reach Feedback & Rules of Engagement Page: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tell the player why an enemy can't be struck (hover box and click log), and add a
main-menu Rules of Engagement page that explains the mechanics from live game data.

**Architecture:**
- One new value class, `StrikePlan`, built by `IsoGridMap.compute_strike_plan()`. It shares
  `compute_reachable_tiles`' Dijkstra, so its fuel figures can't drift from real moves.
- `UIOverlay` draws the plan, and `Battlefield` logs it on click.
- The rules page has its content in `RulesContent` (pure text built from data, so it's testable
  headless) and its drawing in `MainMenu` as a mode.

**Tech Stack:** Godot 4.7, GDScript, the existing `CrtUI` / `PixelFont` / `CrtHotspots` UI kit.

**Spec:** `docs/superpowers/specs/2026-11-01-reach-feedback-and-rules-page-design.md`

## Global Constraints

- No change to movement, fuel or combat rules, AI decisions, or balance numbers. Turning
  literals into named constants must keep their values identical.
- The rules page's numbers must be read from code (`GridTileData`, `GlobalState.chassis_catalog`,
  `MechData`, named constants), never typed into strings.
- The OUT OF REACH figures come from the same cost function and Dijkstra as `compute_reachable_tiles`.
- The breakdown terms always add up to `needs`.
- Rules chapters fit one screen at the smallest virtual viewport, 720x450, with no scrolling.
- The in-battle Field Manual (H) keeps its own text and gains one attack-fuel line.
- All text goes through `CrtUI` (sanitized pixel font, uppercase).

## Review Focus

1. The enemy moves or dies while the hover box is up. The plan is recomputed every hover/refresh,
   and a stale plan must never show for a tile with no enemy. *Test:* Task 2 checks that hovering
   an empty tile clears `strike_plan`.
2. The attacker sits on a city launch tile: next-turn fuel includes the +4 city resupply. Advice
   must stay true. *Test:* Task 1, `test_strike_plan_advice_is_true` replays every advice case.
3. A launch tile is occupied by a friendly unit: it is not a valid launch tile (the existing rule).
   *Test:* Task 1, `test_strike_plan_skips_occupied_launch_tiles`.
4. Mountain-gear Donner and amphibious Falke: breakdown labels and sums with discounts.
   *Test:* Task 1, `test_step_breakdown_sums` across all chassis and terrains.
5. The rules page text overflows the panel when a chapter grows. *Test:* Task 3,
   `test_rules_chapters_fit`.

---

### Task 1: Step-cost breakdown, named constants and the strike plan

**Files:**
- Create: `scripts/battle/StrikePlan.gd`
- Modify: `scripts/data/MechData.gd` (`get_step_fuel_cost`, new constants and breakdown)
- Modify: `scripts/battle/IsoGridMap.gd` (extract the Dijkstra, add `compute_strike_plan`)
- Modify: `scripts/battle/Battlefield.gd` (`_entrench_unit` and `_apply_turn_upkeep` use the new
  constants)
- Test: `tests/battle_screen_tests.gd` (register the new tests in the `_ready` list)

**Interfaces:**
- Produces:
  - `MechData` constants: `WAIT_FUEL := 5`, `WAIT_ENERGY := 4`, `CITY_FUEL := 4`, `CITY_ENERGY := 3`.
    Values are copied from `Battlefield`.
  - `MechData.get_step_fuel_breakdown(from_tile, to_tile) -> Dictionary` with keys:
    - `base: int`, `terrain: String` (the short code, e.g. "MTN")
    - `chassis: int`, `chassis_label: String`, one of "HEAVY", "LIGHT", "AMPHIB", "CLIMB GEAR" or ""
    - `climb: int`
    - `total: int`
  - `get_step_fuel_cost` returns `get_step_fuel_breakdown(...).total`, with identical results to
    today. When `maxi(1, …)` lifts the total, `chassis` absorbs the difference so the terms still add up.
  - `IsoGridMap.compute_strike_plan(unit: MechData, target: Vector2i, occupied_units: Dictionary)
    -> StrikePlan`. It does not touch `reachable_info` or redraw.
  - `StrikePlan` (class_name, RefCounted) fields:
    - `severity: int`, one of `StrikePlan.REACHABLE`, `IN_STRIKING_DISTANCE`, `BEYOND_RANGE`,
      `NO_APPROACH`
    - `needs: int`, `have: int`, `path_fuel: int`, `launch: Vector2i`, `step: Dictionary` (a breakdown)
    - `advice: int`, one of `ADV_NONE`, `ADV_IMPOSSIBLE`, `ADV_WAIT_HERE`, `ADV_MOVE_TO`,
      `ADV_WAIT`, `ADV_MULTI_TURN`
    - `move_to: Vector2i`
  - `StrikePlan` methods:
    - `breakdown_text() -> String`, e.g. "PATH 2 + MTN 5 + HEAVY 1 + CLIMB 1". Zero terms are
      omitted, and the terrain term is always shown.
    - `advice_text() -> String`, using the spec's strings with "IF IT HOLDS" on the next-turn
      advice.
    - `panel_lines() -> PackedStringArray`
    - `log_line(attacker_callsign: String, target_callsign: String) -> String`, matching the spec's
      format: "X CANNOT REACH Y: STRIKE NEEDS 7F (MTN 5 +HEAVY 1 +CLIMB 1), 4F LEFT."

- [ ] **Step 1: Write the failing tests** in `tests/battle_screen_tests.gd`. Build the maps with
  `IsoGridMap.new()` + `load_from_definition(GlobalState.maps[i])`, and units with
  `GlobalState.create_mech_instance`.
  - `test_step_breakdown_sums`: for every chassis × every terrain type × climb 0..2, the breakdown
    terms add up to `total`, and `total == get_step_fuel_cost`. Then, for the Goliath going into a
    mountain from one level below, `{base 5, chassis 1, "HEAVY", climb 1, total 7}`.
  - `test_strike_plan_goliath_mountain`: Iron Bridge, Goliath at (8,6) (plain, elevation 2),
    `current_fuel = 4`, enemy at (8,7) (mountain, elevation 3). Expect:
    - `severity == IN_STRIKING_DISTANCE`, `needs == 7`, `have == 4`, `path_fuel == 0`
    - `advice == ADV_WAIT_HERE`
    - `breakdown_text() == "MTN 5 + HEAVY 1 + CLIMB 1"`
  - `test_strike_plan_matches_reachable`: on all 3 maps, for the Vanguard and Goliath at full fuel,
    for every start tile with an enemy that lands in `reachable_info`, `severity == REACHABLE` and
    `needs == reachable_info[target].fuel_spent`.
  - `test_strike_plan_beyond_range`: Iron Bridge, Goliath at (0,5) at full fuel vs enemy at (8,7) gives
    `BEYOND_RANGE` and `needs > 10`.
  - `test_strike_plan_skips_occupied_launch_tiles`: an enemy whose 4 neighbours are all off-map or
    held by friendlies gives `NO_APPROACH`. Use a map corner with friendlies on both neighbours.
  - `test_strike_plan_advice_is_true`: for every `IN_STRIKING_DISTANCE` plan over all maps, the
    Goliath and Vanguard, and fuel 0..max, replay the advice under the upkeep rules:
    - `ADV_WAIT_HERE`: next turn's fuel `min(max, min(max, have + WAIT_FUEL) + refuel_at(start))
      >= step(start)`
    - `ADV_MOVE_TO`: `min(max, have - path(move_to) + refuel_at(move_to)) >= step(move_to)`
    - `ADV_WAIT`: next turn's fuel after WAIT is enough for `needs`
    - `refuel_at(tile)` is `passive_refuel`, plus `CITY_FUEL` on a city

- [ ] **Step 2: Run the suite and see the new tests fail.** Run `bash tests/run_battle_tests.sh`.
  Expect parse errors or FAILs for the missing `StrikePlan` and `get_step_fuel_breakdown`.

- [ ] **Step 3: Implement.**
  - Extract `_shortest_costs(unit, occupied_units, budget: int) -> Array` (`[best_cost, came_from]`)
    from `compute_reachable_tiles`. Use `budget = 1 << 30` for "no cap", and make
    `compute_reachable_tiles` call it with `current_fuel`.
  - `compute_strike_plan`:
    - Run the uncapped search with the target in `occupied_units`, so it is never expanded through.
    - Launch tiles are the target's in-map neighbours that are reached and not occupied (the start
      tile is allowed), subject to the same "no engagement from a friendly-held tile" rule.
    - Pick L* by the lowest `path + step`. Ties go to the start tile, then to the lower step.
    - `REACHABLE` when `needs <= have`.
    - Run the advice ladder from the spec in order. `ADV_MOVE_TO` picks the reachable L with the
      most spare fuel next turn, and refuel counts `CITY_FUEL` on a city tile (Review Focus 2).
  - `Battlefield` uses `MechData.WAIT_FUEL` etc. in place of the literals 5/4/4/3. The values stay
    the same.

- [ ] **Step 4: Run the suite and the playtest.**
  - `bash tests/run_battle_tests.sh` reports `0 failures`.
  - `godot --headless --path . res://tests/Playtest.tscn` exits 0. Movement must be unchanged.

- [ ] **Step 5: Commit**: `feat: strike plan explains why an enemy is out of reach`.

### Task 2: Out-of-reach readout on hover and in the Comms Log

**Files:**
- Modify: `scripts/ui/UIOverlay.gd` (`_draw_terrain_panel`, the new `strike_plan` var, a
  `MANUAL_LINES` line)
- Modify: `scripts/battle/Battlefield.gd` (`_refresh_hover_telemetry`, `_on_tile_clicked`,
  `_deselect_unit`)
- Test: `tests/battle_screen_tests.gd`

**Interfaces:**
- Consumes: `IsoGridMap.compute_strike_plan`, the `StrikePlan` text methods,
  `MechData.get_step_fuel_breakdown`.
- Produces:
  - `UIOverlay.strike_plan: StrikePlan`, null when there's no plan.
  - `UIOverlay.step_cost_mech: MechData`: the ready selected player mech whose cost the
    `YOUR STEP COST` row uses, or null.
  - `Battlefield.strike_plan_for(coords: Vector2i) -> StrikePlan`: returns null unless every spec
    condition holds (player phase, a ready player unit selected, an enemy on coords, coords not in
    `reachable_info`).

- [ ] **Step 1: Write the failing tests.**
  - `test_out_of_reach_hover_and_click`: instance `res://scenes/Battlefield.tscn` and start the Iron
    Bridge mission. Set TITAN-2 to (8,6) with fuel 4. Make sure no unit sits on (8,7) except
    SPINNE-4, moving units as needed. Then:
    - select TITAN-2 and call `_refresh_hover_telemetry(Vector2i(8,7))`
    - `ui_overlay.strike_plan.severity == IN_STRIKING_DISTANCE`, and `current_forecast` is empty
    - `_refresh_hover_telemetry` on an empty tile sets `strike_plan == null` (Review Focus 1)
    - `_on_tile_clicked(Vector2i(8,7), …)` appends a log line containing "CANNOT REACH" and
      "STRIKE NEEDS 7F", and selects SPINNE-4
    - clicking a `BEYOND_RANGE` enemy adds no log line
  - `test_terrain_panel_draws_plan`: build a `UIOverlay`, set `hovered_tile` and `strike_plan`, and
    call `_on_root_draw()` through a frame. It must not error. The panel rect height computed for the
    plan box covers `panel_lines().size()` lines (expose a
    `_terrain_panel_height() -> float` helper and assert on it).

- [ ] **Step 2: Run them and see them fail.** Run `bash tests/run_battle_tests.sh`.

- [ ] **Step 3: Implement.**
  - `_refresh_hover_telemetry` sets `ui_overlay.strike_plan = strike_plan_for(coords)` and
    `ui_overlay.step_cost_mech`. `_deselect_unit` clears both.
  - `_on_tile_clicked` path 2: if `strike_plan_for(coords)` is `IN_STRIKING_DISTANCE`, play
    `ui_cancel` and add the `log_line`, then select as today. Otherwise keep today's `ui_click`.
  - In `_draw_terrain_panel`:
    - Replace the `FUEL COST` row with `YOUR STEP COST  nF` when `step_cost_mech` is set. It is
      `get_step_fuel_breakdown(hovered, hovered).total`, which is the cost with no climb.
    - Draw the plan where the forecast goes:
      - `IN_STRIKING_DISTANCE`: an amber `C_CURSOR` panel with the title `OUT OF REACH` and
        `panel_lines()` wrapped to width
      - `BEYOND_RANGE` / `NO_APPROACH`: one `C_LABEL_DIM` line
  - Add to `MANUAL_LINES` section 1, after the fuel line: `"   - Attacking moves onto the enemy's
    tile: you pay ITS fuel cost (terrain + chassis surcharge + climb). Hover an enemy to see what a
    strike needs."`

- [ ] **Step 4: Run the suite and the playtest.** Both must pass, as in Task 1 Step 4.

- [ ] **Step 5: Commit**: `feat: OUT OF REACH readout and comms-log reason for unreachable enemies`.

### Task 3: Rules of Engagement page

**Files:**
- Create: `scripts/ui/RulesContent.gd`
- Modify: `scripts/ui/MainMenu.gd` (the `R` key / header row opens it; Esc / back label closes it;
  `_draw_rules`)
- Modify: `scripts/battle/SkirmishEngine.gd` (name the elevation literals; values unchanged)
- Test: `tests/battle_screen_tests.gd`

**Interfaces:**
- Produces:
  - `RulesContent` (class_name, RefCounted), with
    `static func chapters() -> Array[Dictionary]`. Each item is
    `{ "title": String, "blocks": Array }`, and a block is one of:
    - `{"p": String}`: a paragraph
    - `{"key": String}`: an amber key rule
    - `{"table": Array[PackedStringArray]}`: rows; the first row is the header
  - The 7 chapters, titles verbatim: `HOW YOU WIN`, `MOVEMENT & FUEL`, `TERRAIN & HIGH GROUND`,
    `THE CLASH`, `AFTER THE CLASH`, `CHASSIS ROLES`, `FIELD TIPS`.
  - `SkirmishEngine` constants:
    - `ELEV_HIGH_FP_PCT := 12`, `ELEV_HIGH_ENEMY_FP_PCT := 8`, `ELEV_HIGH_ARMOR_PCT := 10`
    - `ELEV_EVA_PER_LEVEL := 4`, `ELEV_CRIT_PER_LEVEL := 5`, `ELEV_ACC_PER_LEVEL := 4`
    - `ELEV_CLIMB_FP_PCT := 10`, `ELEV_CLIMB_ENEMY_FP_PCT := 12`
    - plus whatever DEFEND / RETREAT / crush values the page quotes. Name each one where it already
      lives, with identical values.
  - `MainMenu.show_rules: bool`, `MainMenu.rules_chapter: int`,
    `MainMenu.rules_layout(v: Vector2) -> Dictionary`. The layout returns
    `{"body": Rect2, "list": Rect2}` so tests can measure.

- [ ] **Step 1: Write the failing tests.**
  - `test_rules_chapters_fit`: for each chapter at virtual size 720x450, laid out with
    `MainMenu.rules_layout`, the wrapped line count × `CrtUI.LINE` (tables at one line per row) fits
    `body.size.y`.
  - `test_rules_numbers_come_from_data`:
    - chapter 2 contains `str(GlobalState.chassis_catalog["goliath"].max_fuel)` and the
      mountain cost `GridTileData` reports
    - the example's `needs` equals `get_step_fuel_cost` for the Goliath going plain(L2) → mountain(L3)
    - changing nothing else, the strings contain no glyph `PixelFont` lacks after `CrtUI.sanitize`
  - `test_rules_navigation`: on a `MainMenu` instance:
    - `_activate("rules")` sets `show_rules`
    - Down moves the chapter; key `7` jumps to the last chapter
    - Esc closes the page
    - while the page is open, Enter does not launch a mission

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement.**
  - **Content:** build `RulesContent` per the spec's chapter list.
    - Terrain tables loop over `GridTileData.TerrainType` and call its getters.
    - Chassis rows loop over `GlobalState.chassis_catalog`. Each role line is a short
      `const ROLES := {chassis_id: String}` in `RulesContent`.
    - The worked example comes from the Goliath's `get_step_fuel_breakdown`.
    - Field tips: 6–8 tips, each true under the current rules.
  - **MainMenu header:** a `RULES OF ENGAGEMENT [R]` row left of EXIT, hotspot id `"rules"`.
  - **MainMenu while the page is open:** draw `_draw_rules(v)` instead of the theaters and hangar.
    - The chapter list uses the cursor and `rules_chapter`, with hotspot ids `rules:<i>`.
    - The body draws the blocks: `p` in `C_NUM`, `key` in `C_CURSOR`, table header in `C_LABEL`
      and rows in `C_NUM`.
    - The header has a clickable `[ESC] COMMAND HQ` label, hotspot id `"rules_back"`.
  - **Keys:** with the page open, Up/Down/1-7 switch chapters and Esc/Backspace closes. Enter and
    Space are ignored.
  - **SkirmishEngine:** replace the elevation literals with the constants. Run `tests/matrix.gd`
    before and after and diff the output. It must be identical.

- [ ] **Step 4: Run all suites.**
  - `bash tests/run_battle_tests.sh` reports `0 failures`.
  - `godot --headless --path . -s tests/matrix.gd` output is identical to before.
  - The Playtest exits 0.

- [ ] **Step 5: Commit**: `feat: Rules of Engagement page in Command HQ`.

### Task 4: Documentation

**Files:**
- Modify: `README.md`: in Core Gameplay, Player Command Phase, add the OUT OF REACH readout and the
  rule that attacking pays the enemy tile's fuel. In Controls, add a `R` (main menu) row for the
  Rules of Engagement page. In Architecture & Project Structure, list `StrikePlan.gd` and
  `RulesContent.gd`.
- Modify: `docs/superpowers/specs/2026-11-01-reach-feedback-and-rules-page-design.md`: set the
  status to implemented.

- [ ] **Step 1:** Make the edits.
- [ ] **Step 2:** Check that `README.md`'s numbers agree with the code you touched (WAIT +5,
  terrain costs).
- [ ] **Step 3:** Commit: `docs: rules page, out-of-reach readout and attack fuel rule`.
