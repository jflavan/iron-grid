# FF6-Style Battle Screen Implementation Plan

> **Status (2026-11-01):** this plan describes the presentation-only first pass. The interactive
> command phase has since landed (PR #8) and a few details below are superseded: support turns are
> pure (no follow-up shot, so the `needs_followup` beat key and `test_followup_flags` were removed),
> and the basic gun per chassis is defined once, in `autoload/GlobalState.gd`
> (`MechData.basic_weapon_id`), rather than in the sprite JSON. Everything else still applies.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `SkirmishModal` with a side-view, FF6-style pixel-art battle screen. It plays back the existing `SkirmishResult` unchanged.

**Architecture:**

- **Generator.** A stdlib-only Python generator (`tools/battle_sprites/`) rasterizes every chassis pose, with two-bone leg IK, into palette-swapped PNG sheets. It also writes JSON anchor metadata, backdrops, attachments and a bitmap font, all under `assets/battle/`.
- **Logic.** In Godot, a pure `BattleTimeline` turns a `SkirmishResult` into beats. `BattleLayout` decides sides and elevation from the grid tiles.
- **Rendering.** A `BattleStage` Node2D draws everything at 360×225 inside a SubViewport. `BattleScreen`, a Control, scales it 4× with nearest filtering and keeps `SkirmishModal`'s contract.

**Tech Stack:** Godot 4.7 / GDScript, Python 3 standard library only (`zlib`, `struct`, `json`). Pillow is not installed and must not be required.

**Spec:** `docs/superpowers/specs/2026-10-31-ff6-battle-screen-design.md`. Mockup: `docs/superpowers/specs/2026-10-31-ff6-battle-screen-mockup.html`. Its JS sprite builder, leg IK, Sturmjäger and Brenner part lists, Open Plain backdrop and 88mm timeline are the reference to port.

## Global Constraints

- No change to `SkirmishEngine.gd`, `AIController.gd`, or any rule or damage math. `Battlefield.gd` only changes where it references the modal type.
- Native 360×225, shown at 4× (1440×900) with nearest filtering. Battle area is y 0–152, menu strip is y 153–224.
- CRT skin colours:
  - fill `#0c100c` with scanlines `#0f150f` every other row
  - border `#3ad06a`, inner rule `#1d5a2f`
  - labels `#3ad06a`, names and commands `#e8b040`, numbers `#e8e8d0`, cursor `#ffe080`
- Faction palettes:
  - Coalition: hull `#b4c46a/#6f7f3c/#434d22`, trim `#f6cc6a/#e0a030/#9a6a18`, glow `#ffe070`
  - Syndikat: hull `#d4604c/#8e2a26/#541613`, trim `#a8aeb6/#6d737c/#3e4248`, glow `#ff5040`
  - Shared: metal `#9aa0a8/#5d636b/#33373d`, dark `#56594e/#33362e/#1f211c`, outline `#16120e`
- Sprites are drawn facing right. The right-hand side uses a mirrored copy.
- Never show internal loading. Never show `MISS`. Every damage number shown equals that step's `atk_damage_dealt` or `def_damage_dealt`.
- No ATB. The command box appears only on Coalition actions. Enemy hull is hidden.
- Hold-at-1: visible hull is `max(1, running)` during playback, and becomes `*_armor_after` at the end.
- `godot --headless --path . res://tests/Playtest.tscn` must still exit 0.
- New files go only under `assets/battle/`, `tools/battle_sprites/`, `scripts/battle_screen/`, `tests/` and `scenes/dev/`.

## Review Focus

1. A mech reaches 0 hull mid-fight and still acts. It must hold at 1 and keep acting, and destruction plays only at the end. *Test: Task 5, `test_hold_at_one`.*
2. The Syndikat mech is the attacker, so the defender is Coalition. Sides, the menu-owner panel and the enemy box must still be right. *Test: Task 5, `test_ai_attacker_panels`. Task 4, `test_side_from_approach`.*
3. Skip is pressed mid-action, possibly twice, then confirm. There must be no stale tweens, the signal fires exactly once, and the screen can be reused for the next fight. *Test: Task 6, `test_skip_confirm_reuse`.*
4. Long names and umlauts in a headline (`IRON-1 (Sturmjäger)`, 70+ chars). They must wrap and stay within 344 px. *Test: Task 4, `test_wrap_long_headline`.*
5. Headless runs: the playtest skips through hundreds of fights. There must be no errors and no texture-load failures. *Test: Task 6, a full playtest run.*

---

### Task 1: Generator core + Sturmjäger/Brenner sheets

**Files:**
- Create: `tools/battle_sprites/raster.py`. Part rasterizer (`r`/`c`/`p` parts), edge shading, dither, panel lines, rivets, outline, and palette-index buffers. Ported from the mockup's `buildSprite`.
- Create: `tools/battle_sprites/png.py`. `write_png(path, w, h, rgba_rows)` using zlib and struct.
- Create: `tools/battle_sprites/rig.py`. `solve_knee(hip, ankle, Lt, Ls, forward)`, `bone(p1, p2, w1, w2, ext)`, `leg_parts(leg, off)`, `frame_parts(defn, off, gun_off, flags)`.
- Create: `tools/battle_sprites/chassis.py`. Holds `CHASSIS: dict[str, dict]`, with Sturmjäger as `vanguard` and Brenner as `moloch`, ported from the mockup. Groups are `gun` and `turret`.
- Create: `tools/battle_sprites/poses.py`. The named pose table, shared by every chassis.
- Create: `tools/battle_sprites/generate.py`. CLI: `python3 tools/battle_sprites/generate.py [--out DIR] [--check]`.
- Create: `tools/battle_sprites/test_generator.py` (unittest).
- Output:
  - `assets/battle/mechs/<chassis>_<faction>.png`, where faction is `coalition` or `syndikat`, with frames in one row of cells `w×h`
  - `assets/battle/mechs/<chassis>.json`

**Interfaces:**

Produces `<chassis>.json`:

```json
{"w":112,"h":100,"poses":["idle0",..],"pose_off":{"idle0":[0,0],..},"pose_gun":{"recoil0":-6,..},
 "anchors":{"feet":[x,y],"hull":[x,y],"stacks":[[x,y],..],"muzzles":{"kwk_88":{"p":[x,y],"grp":"gun"},..},
            "attach":{"mast":[x,y],"rangefinder":[x,y]}},
 "variants":{"spent":"moloch_spent"}, "idle_ms":150, "basic_weapon":"kwk_88"}
```

Anchors are given in the rest pose and the unmirrored frame. At runtime, an anchor in group `gun` is shifted by `pose_off + [pose_gun, 0]`, and any other anchor by `pose_off`.

Pose table (`POSES`), as `name: (off, gun)`:

| Pose | Offset | Gun |
|---|---|---|
| `idle0`–`idle5` | `[0,0]`, `[0,1]`, `[1,2]`, `[1,3]`, `[1,2]`, `[0,1]` | 0 |
| `brace` | `[0,1]` | 0 |
| `chamber` | `[0,1]` | −1 |
| `recoil0`–`recoil3` | `[-3,3]`, `[-2,2]`, `[-1,2]`, `[0,1]` | −6, −4, −2, −1 |
| `hit` | `[0,2]` | 0 |
| `stagger` | `[1,4]` | 0 |
| `lunge` | `[6,1]` | 0 |
| `angle` | `[-2,2]` | 0 |

Heavy chassis can set `idle_scale` (Brenner `1.34`) to multiply sink in `idle3`/`idle4`. Brenner `idle3 = [1,4]`.

- [ ] **Step 1: Write failing tests** in `test_generator.py`:
  - `test_knee_is_forward`: `solve_knee((42,57),(32,94),Lt,Ls,1)[0] > 37.6`.
  - `test_png_roundtrip`: write a 3×2 PNG. The file starts with `b'\x89PNG'`, and IHDR width 3 and height 2 parse back.
  - `test_sheet_dimensions`: after generating into a temp dir, `vanguard_coalition.png` width = `w * len(poses)`.
  - `test_deterministic`: two runs into two temp dirs produce byte-identical files.
- [ ] **Step 2:** Run `python3 -m unittest discover -s tools/battle_sprites -v`. Expect FAIL (import errors).
- [ ] **Step 3:** Implement the modules. Rasterize each pose once into palette keys, then colourize per faction.
- [ ] **Step 4:** Run the tests. Expect PASS. Then run `python3 tools/battle_sprites/generate.py`, open the PNGs and eyeball them against the mockup.
- [ ] **Step 5:** Commit: `feat(battle): sprite generator core with Sturmjäger and Brenner`.

### Task 2: Remaining chassis, variants, attachments

**Files:**
- Modify: `tools/battle_sprites/chassis.py`. Add `goliath` (Siegebreaker, about 136×120, super-heavy, 210mm howitzer and quad flak), `falke` (Spähfalke, about 96×92, light strider, autocannon, hip thrusters, rangefinder mount) and `kommandant` (Kaiserstuhl, about 112×106, 105mm, antenna, ECM dish, mast mount).
- Create: `tools/battle_sprites/quad.py`. `donner` (Spinne, about 128×96). Quadruped: four legs, near pair on the hull and far pair as `rear`, rocket pod.
- Variants:
  - `moloch_spent`: Brenner without its reactive bricks. Brenner gets a `bricks` group of 6 small trim rects on the hull.
  - `donner_braced`: Spinne with outrigger struts. Every pose's sink is fixed at `[0,3]`, so the idle has no bob.
- Attachments, per faction:
  - `assets/battle/fx/slab_<faction>.png` (about 40×56)
  - `mast_<faction>.png` (about 6×40)
  - `rangefinder_<faction>.png` (about 30×8)
- Modify: `test_generator.py`. Add `test_all_chassis_present`: for every id in `vanguard, goliath, falke, donner, kommandant, moloch`, plus variants, a sheet and JSON exist for both factions. Every weapon card id in the deck has a muzzle anchor.

Deck per chassis, copied from `GlobalState.gd`:

| Chassis | Deck |
|---|---|
| vanguard | `kwk_88`, `krupp_plate`, `coax_mg` |
| goliath | `morser_210`, `ferro_bulkhead`, `flak_38` |
| falke | `autocannon_50`, `gyro_thruster`, `recon_lock` |
| donner | `rocket_pod`, `plunging_comp`, `anchor_strut` |
| kommandant | `enigma_ecm`, `cmd_override`, `assault_105` |
| moloch | `thermite_lance`, `pile_bunker`, `ablative_shield` |

`basic_weapon` per chassis: vanguard `kwk_88`, goliath `flak_38`, falke `autocannon_50`, donner `rocket_pod`, kommandant `assault_105`, moloch `thermite_lance`.

- [ ] **Step 1:** Add `test_all_chassis_present`. Run it and expect FAIL.
- [ ] **Step 2:** Design and implement the four chassis and variants, in the same visual language: shading, rivets, panel lines, insignia, knee discs, a piston on the front leg, exhaust stacks.
- [ ] **Step 3:** Run the tests, expect PASS. Regenerate the assets and eyeball every sheet.
- [ ] **Step 4:** Commit: `feat(battle): remaining chassis designs, variants and attachments`.

### Task 3: Backdrops + bitmap font

**Files:**
- Create: `tools/battle_sprites/backdrops.py`. `render_backdrop(terrain) -> rgba rows (360×152)` for `plain` (port the mockup), `road`, `river`, `forest` (trench timber), `city` and `mountain`. Same style: banded dithered sky, layered silhouettes, dithered ground bands, props.
- Create: `tools/battle_sprites/font.py`. A 5×7 glyph table with 6 px advance, as strings of `#` and `.`. It covers `A–Z 0–9`, space, and `. , : ; ! ? - + / ( ) % ' " # & < > = _ [ ]`, plus `Ä Ö Ü ä ö ü ß`. Lowercase maps to uppercase.
- Output:
  - `assets/battle/backdrops/<terrain>.png`
  - `assets/battle/font/font5x7.png`: white glyphs on transparent, in one row of 6×8 cells
  - `assets/battle/font/font5x7.json`: `{"advance":6,"height":8,"chars":"…"}`
- Modify: `test_generator.py`. Add `test_backdrops_and_font`: six 360×152 PNGs exist, and the font JSON `chars` contains `"Ä"` and `"9"`.

- [ ] **Step 1:** Write the test. Run it and expect FAIL.
- [ ] **Step 2:** Implement the backdrops and font, then regenerate.
- [ ] **Step 3:** Run the tests, expect PASS. Eyeball the backdrops.
- [ ] **Step 4:** Commit: `feat(battle): terrain backdrops and 5x7 bitmap font`.

### Task 4: Godot data layer: sprite bank, pixel font, layout

**Files:**
- Create: `scripts/battle_screen/MechSpriteBank.gd` (`class_name MechSpriteBank`, RefCounted, cached static loaders):
  - `static func get_meta(chassis: String) -> Dictionary`
  - `static func get_sheet(chassis: String, faction: int) -> Texture2D`
  - `static func frame_rect(chassis: String, pose: String) -> Rect2`
  - `static func anchor(chassis: String, name: String, pose: String, mirrored: bool) -> Vector2`. Handles `muzzles/<card_id>`, `feet`, `hull`, `stacks/<i>` and `attach/<name>`, and applies `pose_off` and `pose_gun`.
- Create: `scripts/battle_screen/PixelFont.gd` (`class_name PixelFont`):
  - `static func draw_text(ci: CanvasItem, text: String, pos: Vector2, color: Color) -> void`
  - `static func text_width(text: String) -> int`
  - `static func wrap(text: String, max_px: int) -> PackedStringArray`
- Create: `scripts/battle_screen/BattleLayout.gd` (`class_name BattleLayout`):
  - `static func attacker_on_left(from: Vector2i, target: Vector2i) -> bool`. True when `(from.x - from.y) < (target.x - target.y)`. A tie can't happen for orthogonal neighbours, but default it to `true`.
  - `static func elevation_offsets(elev_diff: int) -> Vector2i`. Returns `(atk_dy, def_dy)` in native px, at 4 px per level, with the higher mech raised (negative y). Clamp to ±12.
  - `const BACKDROP_BY_TERRAIN := {PLAIN:"plain", ROAD:"road", RIVER:"river", FOREST:"forest", CITY:"city", MOUNTAIN:"mountain"}`
- Create: `tests/BattleScreenTests.tscn` + `tests/battle_screen_tests.gd`. Same `_check` and exit-code pattern as `playtest.gd`.

- [ ] **Step 1: Write failing tests:**
  - `test_sprite_bank_loads`: for all 6 chassis and both factions, `get_sheet` is non-null and its width equals `w * poses.size()`.
  - `test_anchor_mirrors`: `anchor("vanguard","feet","idle0",true).x == w - anchor(...,false).x`.
  - `test_recoil_moves_muzzle`: the `kwk_88` muzzle x at `recoil0` is less than at `brace` by 9 (−3 body, −6 gun).
  - `test_side_from_approach`: from (3,2) to (4,2) is left; (4,2)→(3,2) is right; (3,2)→(3,3) is right; (3,3)→(3,2) is left.
  - `test_elevation_offsets`: `elevation_offsets(2) == Vector2i(-8,0)`, `(-1) == Vector2i(0,-4)`, `(0) == Vector2i.ZERO`.
  - `test_wrap_long_headline`: wrapping `"TACTICAL VICTORY (4-2) — IRON-1 (Sturmjäger) DISLODGED KRIEGS-SYNDIKAT WALKER!"` to 344 gives every line `text_width <= 344` and more than one line.
- [ ] **Step 2:** Run `godot --headless --path . res://tests/BattleScreenTests.tscn`. Expect a non-zero exit.
- [ ] **Step 3:** Implement the three scripts. Run `godot --headless --path . --import` first so the PNGs get `.import` files, and commit those.
- [ ] **Step 4:** Run the tests. Expect exit 0.
- [ ] **Step 5:** Commit: `feat(battle): sprite bank, pixel font and layout helpers`.

### Task 5: BattleTimeline (pure)

**Files:**
- Create: `scripts/battle_screen/BattleTimeline.gd` (`class_name BattleTimeline`, RefCounted):
  - `static func build(result: SkirmishEngine.SkirmishResult) -> BattleTimeline`
  - `var beats: Array[Dictionary]`. Each beat has these keys:
    - `step` (int)
    - `actor` (`"atk"` or `"def"`)
    - `actor_faction` (int)
    - `card_id`, `card_name`, `card_type` (String)
    - `command_row` (int: 0 FIGHT, 2 ARMOR, 3 TACTIC; −1 when the actor is Syndikat)
    - `needs_followup` (bool: true for ARMOR/TACTICAL)
    - `damage` (int)
    - `target` (`"atk"` or `"def"`)
    - `capture_text` (String: `""`, or `"OVERMATCH: N SYSTEM(S) CAPTURED"`, or `"TACTICAL PLUS OVERLOAD: N FLIPPED"`)
    - `hull_after` (`{"atk": int, "def": int}`, hold-at-1 values)
    - `soften_from` (String card id of the defensive effect this hit consumes, or `""`)
  - `var start_hull: Dictionary` and `var end_hull: Dictionary` (`*_armor_before` and `*_armor_after`)
  - `var coalition_side: String` (`"atk"` or `"def"`)
  - `var headline: String`
  - `var ending: String` (`"destroy_def"`, `"destroy_atk"`, `"destroy_both"`, `"pushback"` or `"repelled"`)
- Weapons go to `FIGHT`. `WEAPON` stays unused for the follow-up interactive phase.
- Soften rules: `krupp_plate`, `gyro_thruster` and `ablative_shield` set a pending soften on their actor. The opponent's next beat consumes it through `soften_from`.

- [ ] **Step 1: Write failing tests** in `battle_screen_tests.gd`. Build `SkirmishResult`s with `SkirmishEngine.resolve_skirmish(..., false)` from `GlobalState` mech templates.
  - `test_damage_sums`: the sum of `damage` over attacker beats equals `total_dmg_to_defender`, and over defender beats equals `total_dmg_to_attacker`.
  - `test_hold_at_one`: give the defender `current_armor = 5`. Every beat's `hull_after.def >= 1`, `end_hull.def == 0`, and `ending == "destroy_def"`.
  - `test_ai_attacker_panels`: AI attacker vs player defender. `coalition_side == "def"`. Attacker beats have `command_row == -1`, and defender beats with a weapon card have `command_row == 0`.
  - `test_followup_flags`: on vanguard, step 2 (`krupp_plate`) has `needs_followup` true. The next defender beat has `soften_from == "krupp_plate"`.
  - `test_capture_text`: any beat whose step has `flipped_slots.size() > 0` has non-empty `capture_text`.
- [ ] **Step 2:** Run the tests. Expect FAIL.
- [ ] **Step 3:** Implement `BattleTimeline.build`.
- [ ] **Step 4:** Run the tests. Expect PASS.
- [ ] **Step 5:** Commit: `feat(battle): battle timeline built from SkirmishResult`.

### Task 6: BattleStage + BattleScreen + integration (idle, panels, generic action)

**Files:**
- Create: `scripts/battle_screen/BattleStage.gd` (`class_name BattleStage`, Node2D, lives in the 360×225 SubViewport).
  - `func setup(result, timeline) -> void`
  - `func advance(delta: float) -> void`: timeline time × speed
  - `func skip_to_end() -> void`
  - `var finished: bool`
  - `_draw` draws, in order: backdrop, shadows, mechs (pose, flash and shake), FX layer, panels, banner, numbers.
  - Per-mech runtime state: `chassis`, `faction`, `mirrored`, `base_pos`, `pose`, `flash_t`, `shake`, `variant`, `braced`, `slab`, `armed_bricks`.
- Create: `scripts/battle_screen/BattleScreen.gd` (`class_name BattleScreen`, Control, full rect, mouse stop). Holds the SubViewport (360×225, `transparent_bg=false`) and a TextureRect at 1440×900, centred, `texture_filter = NEAREST`. Black fill behind it.
  - **Contract:** `signal resolution_confirmed(result)`, `func start_showdown(result)`, `var _all_steps_done: bool`, `func _on_skip_pressed()`, `func _on_confirm_pressed()`.
  - Space/Enter: skip, then confirm (same as today).
  - `S` toggles speed between 1× and 2×.
- Modify: `scripts/ui/UIOverlay.gd:15,53-55`. `skirmish_modal` becomes a `BattleScreen`. Keep the property name.
- Modify: `tests/playtest.gd:283` and `tests/balance.gd:65`. Change the type annotation `SkirmishModal` to `BattleScreen`.
- Delete: `scripts/ui/SkirmishModal.gd` and `.uid`, once nothing references them.
- This task uses a generic shell attack for every card. Tasks 7 and 8 replace it per card.

- [ ] **Step 1: Write failing test** `test_skip_confirm_reuse`: instance a `BattleScreen`, call `start_showdown(r1)`, `_on_skip_pressed()` twice, then `_on_confirm_pressed()`. The signal fires exactly once with `r1` and `visible == false`. Then `start_showdown(r2)` and confirm twice; it fires once with `r2`.
- [ ] **Step 2:** Run it. Expect FAIL.
- [ ] **Step 3:** Implement the stage, screen and integration. Port the mockup's panels and CRT skin, the hidden enemy hull, and `Sturmjäger`-style idle cycling at `idle_ms`.
- [ ] **Step 4:** Run `BattleScreenTests` (exit 0), then the full `Playtest.tscn` (exit 0, 0 failures).
- [ ] **Step 5:** Run the game windowed and screenshot a fight via the Godot MCP or a capture. Confirm the layout matches the mockup.
- [ ] **Step 6:** Commit: `feat(battle): battle screen replaces skirmish modal`.

### Task 7: Weapon card animations

**Files:**
- Create: `scripts/battle_screen/BattleFX.gd` (`class_name BattleFX`, static draw helpers on a CanvasItem): `blob`, `muzzle_flash(f)`, `explosion(k)`, `tracer`, `smoke_puffs`, `sparks`, `damage_number(value, t)`.
- Create: `scripts/battle_screen/WeaponAnims.gd` (`class_name WeaponAnims`):
  - `static func duration(card_id: String, quick: bool) -> float`
  - `static func run(stage: BattleStage, actor: Dictionary, target: Dictionary, card_id: String, t: float, quick: bool) -> Dictionary`

  `run` sets actor and target pose, flash and shake on the state dicts, queues draw commands, and returns `{impact: bool}` the frame the hit lands.

| Card | Animation |
|---|---|
| `kwk_88` | Exact mockup timeline: `chamber` → `recoil0..3` → tracer shell → impact |
| `coax_mg` | 10 tracer dashes from the MG muzzle, many small sparks |
| `morser_210` | `recoil` heavy, tall parabolic lob, big impact with ground dust |
| `flak_38` | 4 alternating flashes and 4 bursts |
| `autocannon_50` | 3-round burst |
| `rocket_pod` | 6 rockets with smoke trails arcing in, staggered impacts |
| `assault_105` | Direct heavy shell, bigger flash |
| `thermite_lance` | Flame stream (layered blobs) with heat shimmer, burning on the target |
| `pile_bunker` | `lunge` pose crosses the gap, then spike impact, then return |

- `quick = true` is the follow-up version, at about 55% duration (no long wind-up).
- An impact frame applies the step's damage number and consumes `soften_from`. Task 8 draws the soften visuals.

- [ ] **Step 1: Write failing test** `test_every_weapon_has_anim`: for each BALLISTIC, ARTILLERY or THERMAL card in `GlobalState.card_catalog`, `WeaponAnims.duration(id,false) > 0`. Also `run` over `t in [0, duration]` at 1/60 steps returns `impact == true` exactly once.
- [ ] **Step 2:** Run it. Expect FAIL.
- [ ] **Step 3:** Implement. Wire the stage so weapon beats use `WeaponAnims`.
- [ ] **Step 4:** Run the tests and the playtest.
- [ ] **Step 5:** Commit: `feat(battle): per-weapon attack animations`.

### Task 8: Support card effects, soften, stagger and endings

**Files:**
- Create: `scripts/battle_screen/SupportAnims.gd` (`class_name SupportAnims`):
  - `static func duration(card_id) -> float`
  - `static func run(stage, actor, target, card_id, t) -> void`

  Each card, per spec §5.4:

| Card | Effect |
|---|---|
| `krupp_plate` | `angle` pose with a glacis glint, sets the actor's `soften = "ricochet"` |
| `ferro_bulkhead` | Slab drops from above with a dust shockwave, then `slab = true` |
| `anchor_strut` | Switch to the `donner_braced` variant with a dust kick |
| `ablative_shield` | Bricks glow amber, `armed_bricks = true` |
| `gyro_thruster` | Steam jets, then `soften = "sidestep"` |
| `recon_lock` | Rangefinder attachment extends, glint, reticle slides on and snaps to `LOCK` |
| `plunging_comp` | CRT inset with spinning dials, then a dotted arc. The follow-up shot flies along that arc. |
| `enigma_ecm` | Radio rings, then the target's sprite is drawn in horizontal slices offset by noise |
| `cmd_override` | Mast attachment telescopes up, a signal ring rises, chatter box `HQ: FIRE MISSION CONFIRMED`, and a green glow on the actor |

- Stage flow for a support beat: banner, then `SupportAnims.run`, then `WeaponAnims.run(basic_weapon, quick=true)`, which carries the damage.
- Soften on impact:
  - `ricochet`: spark shower off the glacis plus a deflected tracer.
  - `sidestep`: afterimages and the target offset sideways 6 px during impact.
  - Armed bricks: brick-burst explosion in front of the target, then the target switches to the `moloch_spent` variant.

  The damage number is always the real value.
- Stagger: while a mech's displayed hull is held at 1 (true running hull ≤ 0) and it isn't acting, show the `stagger` pose plus periodic sparks and smoke.
- Endings, after the last beat:
  - `destroy_*`: about 6 staggered explosions over 1.6 s, white flashes, then the sprite sinks below the ground line (clipped at feet y) and darkens to a wreck silhouette.
  - `pushback`: the defender eases 8 px away and sinks.
  - `repelled`: the attacker eases 8 px back.

  Then the result banner shows the wrapped `headline` with a `CONFIRM [SPACE]` prompt.

- [ ] **Step 1: Write failing test** `test_every_support_has_anim`: every ARMOR or TACTICAL card id in the catalog has `SupportAnims.duration > 0`. A stage driven from `t = 0` to `finished` for the timeline of each chassis vs every chassis (36 pairings) raises no errors and ends with `finished == true`.
- [ ] **Step 2:** Run it. Expect FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the tests and the playtest.
- [ ] **Step 5:** Commit: `feat(battle): armor/tactical effects, soften, stagger and endings`.

### Task 9: Preview scene + docs

**Files:**
- Create: `scenes/dev/BattlePreview.tscn` + `scripts/battle_screen/BattlePreview.gd`. Keyboard controls:
  - ←/→ cycle the attacker chassis
  - ↑/↓ cycle the defender chassis
  - `T` cycles terrain
  - `F` swaps faction sides
  - `Enter` replays a fight built with `resolve_skirmish(..., false)` on duplicates
  - `1`–`9` play a single card
- Modify: `README.md`. Rewrite the Skirmish Resolution section and the architecture tree (new folders, generator command). Add a "Battle Art Pipeline" section.

- [ ] **Step 1:** Implement the preview. Open it windowed and screenshot each chassis and backdrop.
- [ ] **Step 2:** Update the README.
- [ ] **Step 3:** Final verification:
  - `python3 -m unittest discover -s tools/battle_sprites`
  - `python3 tools/battle_sprites/generate.py --check`, which exits 0 when the output is identical
  - `BattleScreenTests.tscn` exits 0
  - `Playtest.tscn` exits 0
- [ ] **Step 4:** Commit: `docs: battle screen art pipeline and preview scene`.
