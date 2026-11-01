# Out-of-Reach Feedback & Rules of Engagement Page: Design

Date: 2026-11-01. Status: implemented on `feat/reach-feedback-rules-page` (see the plan in
`docs/superpowers/plans/2026-11-01-reach-feedback-and-rules-page.md`). The design-review questions
were settled as marked "my call". The HUD box shortened its first line to `NEEDS 7F, HAVE 4F` and
wraps the breakdown between terms so it fits the 140px panel.

## Why

A player selected TITAN-2 (Goliath chassis), hovered an enemy on a mountain, and could not attack
it. Nothing on screen said why. The cause is a rule, not a bug: an attack is a move onto the
enemy's tile, so the attacker pays that tile's full step cost (`MechData.get_step_fuel_cost`:
terrain base + chassis surcharge + 1 per level climbed). For the Goliath (10 max fuel, +1 off-road
surcharge, +4 fuel per turn), striking a mountain one level up costs 7, so it can never strike a
mountain after it has moved. A headless probe confirmed this on every map: with the fuel a Goliath
has after a move, it reaches 0% of mountain tiles, even adjacent ones.

The user chose to **keep the mechanic** and make it visible, and to add a main-menu page that
explains the battle mechanics and gives strategy tips up front.

## Goals

1. When a ready player unit is selected and the player hovers an enemy it cannot strike, the game
   says so, says why (fuel breakdown) and says what to do.
2. Clicking such an enemy also explains it, in the Comms Log.
3. A **Rules of Engagement** page reachable from the main menu gives a fuller, high-level
   breakdown of the mechanics and strategy, so a player understands the game before a mission.

## Non-goals

- No change to movement, fuel or combat rules, AI decisions, or balance numbers.
- The in-battle Field Manual (H) is **not** replaced by the new page. It keeps its own shorter text
  (user's decision).
- No on-map marker for unaffordable enemies (option B in the mockups; the user picked A + C only).

## Anti-goals (fail even if it "works")

- Numbers on the new page that disagree with the game's data. Terrain costs, modifiers, chassis
  fuel, refuel and surcharges must be read from code (`GridTileData`, `GlobalState.chassis_catalog`,
  `MechData`), not typed into strings.
- An out-of-reach explanation whose fuel figure differs from what the move would actually cost.
  It must use the same cost function as `IsoGridMap.compute_reachable_tiles`.
- A rules page that needs scrolling or breaks the CRT pixel style of the main menu.

## Part 1: Out-of-reach feedback in battle

### When it applies

All of these must be true:

- It is the player phase.
- A **player** unit that has not moved is selected.
- The hovered (or clicked) tile holds an **enemy** unit.
- That tile is **not** in `grid_map.reachable_info`.

### What it computes (one shared helper)

A single function (suggested home: `IsoGridMap`, next to `compute_reachable_tiles`, so both use
the same costs and occupancy rules) returns a **strike plan** for attacker → enemy tile.

Definitions:

- **Launch tile**: one of the enemy's 4 neighbours that the attacker may attack from under the
  existing rules: on the map, not another unit (the attacker's own start tile is allowed), and not
  reached *through* an enemy.
- `path(L)`: cheapest fuel from the attacker's tile to launch tile L, using the same Dijkstra rules
  as `compute_reachable_tiles` but **without the fuel cap**. It is 0 when L is the start tile.
- `step(L)`: `get_step_fuel_cost(L, enemy_tile)`.
- `have`: the attacker's current fuel. `max`: its max fuel. `refuel`: its `passive_refuel`.
- `WAIT_FUEL`: the +5 from WAIT/REFUEL, exposed as a named constant and used by
  `Battlefield._entrench_unit` too.

The plan picks the launch tile L* with the lowest `path(L) + step(L)`. Ties go to the start tile,
then to the lower `step`. It reports:

- `needs = path(L*) + step(L*)` and `have`
- the breakdown of `needs`: `PATH n` (omitted when 0), terrain base, chassis adjustment, climb.
  The terms always add up to `needs`.

**Severity** (my call, after the design review: show the loud treatment only when the player is
actually in striking distance):

- `IN_STRIKING_DISTANCE`: some launch tile is reachable this turn (`path(L) <= have`), but no launch
  tile has `path(L) + step(L) <= have`. This is the case the user hit. It gets the full OUT OF
  REACH box, the click log line and the `ui_cancel` sound.
- `BEYOND_RANGE`: no launch tile is reachable this turn. The panel shows one quiet dim line,
  `BEYOND MOVE RANGE (NEEDS nF)`. There is no sound and no log line, and clicking still just
  selects the enemy.
- `NO_APPROACH`: the enemy has no launch tile at all (boxed in). Panel line: `NO OPEN APPROACH TILE`.
  Quiet.

**Advice must be true** (my call, after the design review). For `IN_STRIKING_DISTANCE` it simulates
next turn under the game's real rules: moving ends the unit's action, next turn's fuel is
`min(max, left + refuel)`, and WAIT gives `min(WAIT_FUEL, max - have)` now and then refuel. The
enemy is assumed to stay put, and the advice text says "IF IT HOLDS". It checks these in order:

1. `IMPOSSIBLE`: `step(L) > max` for every launch tile. Advice: `THIS CHASSIS CAN'T CLIMB THERE`.
2. If the attacker already stands on a launch tile and WAIT now gives enough next turn
   (`min(max, min(max, have + WAIT_FUEL) + refuel) >= step(start)`): `WAIT/REFUEL HERE, STRIKE NEXT
   TURN`.
3. If some launch tile L is reachable now and `min(max, have - path(L) + refuel) >= step(L)`: `MOVE TO
   x,y, STRIKE NEXT TURN`. Pick the L that leaves the most spare fuel.
4. If WAIT now gives enough to strike via L* next turn: `WAIT/REFUEL, STRIKE NEXT TURN`.
5. Otherwise: `REFUEL FIRST: TAKES 2+ TURNS`.

### Chassis-adjustment labels

`HEAVY +1` (`fuel_efficiency_mod > 0`), `LIGHT -1` (`< 0`), `AMPHIB -2` (river with
`amphibious_gear`), `CLIMB GEAR -2` (mountain with `mountain_gear`). The labels follow the branches
in `MechData.get_step_fuel_cost` exactly. Road gets no surcharge. If the mountain-gear climb
discount applies, the climb figure shown is the discounted one.

## Part 2: Rules of Engagement page (main menu)

### Entry and exit

- A `RULES OF ENGAGEMENT` row in the main-menu header, left of `EXIT`, clickable (`CrtHotspots`)
  and also opened with a key (builder's call; must not clash with the existing keys
  1-3/arrows/Enter/Space).
- Esc, and a clickable `[ESC] COMMAND HQ` label in the page header, return to Command HQ.

### Layout (option A, "chapters")

The page is drawn in the existing CRT pixel style (`CrtUI`, `PixelFont`, integer pixel scale), as
a mode of `MainMenu` or a sibling Control (builder's call):

- Header panel: `RULES OF ENGAGEMENT` + the back label.
- Left column: chapter list, numbered. The current one has the cursor. Up/Down, 1-7 and clicks
  change chapters.
- Right panel: the selected chapter, which must fit on one screen at the smallest supported
  viewport (no scrolling).

### Chapters and content

Values in `{}` come from game data at draw time.

1. **HOW YOU WIN.** Turn flow (player phase → clashes → Syndicate phase). The three mission types
   and their win/loss rules, from `Battlefield._check_victory_conditions`:
   - Pitched Battle: hold every objective at turn end, or the majority at the turn limit (ties
     go to more walkers left).
   - Defense: survive to the turn limit; you lose if all your objectives are taken at turn end.
   - Offense: hold an HQ bunker at turn end before the turn limit.
   - Wiping out the enemy wins any mission; losing all walkers loses. Captures count only at the
     end of a full turn, so they must survive the enemy phase.
2. **MOVEMENT & FUEL.** Every step costs terrain fuel + 1 per level climbed. **Attacking means
   stepping onto the enemy's tile, so you pay that tile's fuel.** A terrain fuel table
   `{GridTileData.get_base_fuel_cost}`. Chassis adjustments `{fuel_efficiency_mod, amphibious_gear,
   mountain_gear}` by chassis. Refuel: `{passive_refuel}` per turn by chassis, WAIT/REFUEL +5,
   city +4. A worked example computed from the Goliath's data (mountain one level up = 7 of its 10).
3. **TERRAIN & HIGH GROUND.** A table of ATK/DEF/EVA modifiers by terrain
   `{get_attack/defense/evasion_modifier_pct}`. Elevation advantage per level (values from
   `SkirmishEngine`). Cities repair and resupply. Rivers are a trap.
4. **THE CLASH.** Turn order by SPD (attacker round-1 bonus, entrenched defender bonus). ATTACK
   (0 EN), TECH (costs EN; ARMOR/TACTIC TECHs once per battle), DEFEND (halves the next hit that
   lands, +EN, can't stack), RETREAT. Entrenchment (WAIT) bonuses.
5. **AFTER THE CLASH.** Attacker wins: defender pushed back to a retreat tile and the attacker
   takes the tile; no retreat tile means crush damage. Attacker repelled or retreats: it falls
   back to its approach tile. A defender keeps entrenchment unless the attacker won.
6. **CHASSIS ROLES.** One line per chassis from `chassis_catalog` (name, class, fuel
   `{max_fuel}+{passive_refuel}`, gear), plus a one-line role written for the page.
7. **FIELD TIPS.** About 6–8 short tips, drafted by the builder, for example: strike mountains
   from an adjacent tile with a full tank; heavies use roads; don't stop in rivers; hold cities to
   repair; Falke and Donner for ridges; WAIT next to a target to strike next turn.

The rule values the builder can't read directly from a data getter (elevation bonuses, SPD
bonuses, WAIT bonuses, city resupply amounts) should be exposed as constants where they live and
read from there, rather than repeated as literals in the page text.

## In-battle Field Manual (H)

Keeps its own shorter text with one added line in section 1: attacking means moving onto the
enemy's tile and paying its fuel cost. (After code review: the list became
`UIOverlay.manual_lines()`, which reads its numbers from the same constants as the Rules page, and
it points to the Rules page.)

## Docs

`README.md`: mention the Rules of Engagement page (Controls and gameplay sections) and the
out-of-reach readout. The map tactical tips need no change.

## Verification

- `bash tests/run_battle_tests.sh` stays green. New tests there cover:
  - the strike-plan helper:
    - the Goliath next to a mountain one level up with 4 fuel gives needs 7, `IN_STRIKING_DISTANCE`,
      the advice WAIT/REFUEL HERE, and terms adding up to 7;
    - a distant target gives `BEYOND_RANGE`;
    - for a target that *is* reachable, `needs` equals `reachable_info[target].fuel_spent` (same
      cost model);
    - every piece of advice it gives holds when replayed under the upkeep/WAIT rules;
  - the rules page draws every chapter at the smallest viewport without text overflowing the
    panel (the same kind of check the existing hangar-width test does).
- `godot --headless --path . res://tests/Playtest.tscn` still passes (no gameplay change).
- Manual check: run the game, select TITAN-2 on Iron Bridge, hover and click SPINNE-4, and open
  the rules page and walk all chapters.

## Left to the builder

The exact helper name and placement, the key that opens the page, whether the page is a mode of
`MainMenu` or its own Control, the tip wording, and the chapter text wording (within the content
above).
