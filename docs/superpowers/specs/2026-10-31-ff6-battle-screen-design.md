# FF6-Style Battle Screen: Design

**Date:** 2026-10-31
**Status:** Draft, awaiting approval
**Mockup reference:** [`2026-10-31-ff6-battle-screen-mockup.html`](2026-10-31-ff6-battle-screen-mockup.html). Open it in a browser. It's the approved v6 mockup: Open Plain backdrop, Sturmjäger vs Brenner, articulated idle, full 88mm attack. Click or press Space to pause, and use ← / → to step through it.

---

## 1. Intent

Fights in Iron Grid currently resolve in `SkirmishModal`, a telemetry panel with an animated 3×3 Triple Triad board. The owner wants fights to *feel* like Final Fantasy VI battles. When one walker engages another, the game cuts from the isometric grid to a side-view pixel-art battle screen. The two mechs face off in front of a backdrop picked by the terrain, and each card plays as an animated attack or effect. Then the game cuts back to the grid.

This phase is **presentation only**. The battle screen plays back the `SkirmishResult` that `SkirmishEngine.resolve_skirmish` already produces. A later follow-up will change the mechanics, with real player commands and turn-based choices, and this screen is built so that follow-up can plug in.

## 2. Goals

1. A new battle screen that **fully replaces** `SkirmishModal` as the presentation of every skirmish, for player and AI attacks alike.
2. True pixel art in FF6 style for all **6 chassis** in **2 faction palettes**, at the size and detail of the approved mockup.
3. An **articulated idle** for every chassis. The feet are planted and the legs are a two-bone hip→knee→ankle rig, so the body dips and leans while the knees push forward and the shins tilt. Leg motion has to visibly articulate; it must not look like the top half sliding.
4. A distinct **animation for each of the 18 equipment cards**. Weapons follow the attack structure in §5.3, and armor and tactical cards follow §5.4.
5. **6 terrain backdrops**, one per `GridTileData.TerrainType`.
6. Sprite placement driven by grid geometry: approach direction and elevation (§5.6).
7. Art produced by a **re-runnable generator** that exports PNG sprite sheets into the repo, so designs can be tweaked and regenerated.

## 3. Non-goals

- **No mechanics changes.** `SkirmishEngine`, damage math, card rules, retreat/push-back logic, AI and turn flow stay byte-for-byte identical. Every number shown on screen comes from `SkirmishResult` and `BoutStep`.
- **No ATB.** There's no gauge and no real-time element.
- **No interactive command menu yet.** The menu is drawn and its cursor moves on its own (§5.5). Player choice arrives in the follow-up.
- **No 3×3 board display.** The owner chose to hide the board entirely. Captures are reported as text only (§5.5).
- No changes to the grid view, the main menu or the HUD outside the battle screen.
- No music changes.

## 4. Anti-goals: failure even if it "works"

- Legs that slide or bob as a rigid block instead of articulating at the knee.
- Showing machine internals the crew wouldn't see. **Loading happens inside the turret and is never animated** (the owner explicitly cut this).
- Damage numbers or outcomes on screen that disagree with `SkirmishResult`. For example, a "MISS" over a step that actually dealt damage.
- Breaking `tests/playtest.gd` (headless full-mission runs) or making skirmishes unskippable.
- Blurry scaling. Pixels must stay crisp (nearest-neighbour filtering, integer scale).

## 5. Decided design

### 5.1 Screen and skin

- Native canvas: **360×225**, rendered at **4×** to fill the 1440×900 viewport with nearest-neighbour filtering. The project uses `stretch/mode=canvas_items` and `aspect=expand`, so the builder decides how to keep the 4× integer scale and how to centre or letterbox on other window sizes.
- Layout follows the mockup. The battle area is the top ~152 px, and the menu strip is the bottom ~72 px.
- **Skin: the Iron Grid CRT look (mockup option B), not FF6 blue.** Panels have a near-black green fill (`#0c100c`) with scanlines every other row, a 1 px `#3ad06a` border and an inner `#1d5a2f` rule. Labels are `#3ad06a`, names and commands are amber `#e8b040`, numbers are `#e8e8d0`, and the cursor is `#ffe080`.
- Menu strip panels:
  - **Left: enemy box.** The Syndikat mech's callsign, its faction tag, and the **battleground** terrain short code and elevation, i.e. the `target_tile` that also picks the backdrop (e.g. `PLN 100m`). It shows the same tile whichever side attacked. *(Builder-check call.)*
  - **Text length.** Real callsigns and `summary_headline` strings are longer than 360 px allows at 8 px per character. The builder wraps text or uses the short callsign, and must handle umlauts (`Sturmjäger`).
  - **Middle: command box.** Four rows: `FIGHT`, `WEAPON`, `ARMOR`, `TACTIC`, with a blinking triangle cursor. It's hidden while an action plays and returns between actions.
  - **Right: own stats.** The player-side mech's callsign, a **FUEL** gauge with `cur/max` and a **HULL** gauge with `cur/max`.
- **Top banner.** A centred CRT panel shows the name of the card being used for each action, FF6 style.
- Pixel font: the mockup used Press Start 2P at 8 px native. The builder picks or makes a bitmap font that renders crisp at native resolution.

### 5.2 Mech sprites

- One design per chassis, palette-swapped by faction:
  - **Coalition (player):** hull `#b4c46a / #6f7f3c / #434d22`, trim `#f6cc6a / #e0a030 / #9a6a18`, viewport glow `#ffe070`.
  - **Syndikat (AI):** hull `#d4604c / #8e2a26 / #541613`, trim `#a8aeb6 / #6d737c / #3e4248` (gunmetal), glow `#ff5040`.
  - Shared metal `#9aa0a8 / #5d636b / #33373d`, dark `#56594e / #33362e / #1f211c`, and outline `#16120e`.
- Scale: about **100–120 px tall** at native resolution, filling most of the battle area like FF6 boss sprites. Sturmjäger ≈ 112×100 and Brenner ≈ 128×116 are the reference. A super-heavy (Siegebreaker) may be bigger and a light strider (Spähfalke) smaller, but none should drop back toward v1's ~50 px.
- Detail level matches the mockup:
  - three-tone shading lit from the upper left, with a dithered lower-third shadow
  - automatic 1 px dark outline
  - rivets, bevelled panel lines, faction insignia and trim stripe
  - visible joints (knee discs), hydraulic pistons, exhaust stacks with smoke
- **Sturmjäger** and **Brenner** are approved as drafted in the mockup. The other four (Siegebreaker, Spähfalke, Spinne, Kaiserstuhl) are new designs that follow the README chassis descriptions and the same visual language. The owner reviews them in the preview scene (§7).
  - Spinne is a *quadruped*. The rig needs four legs (two pairs) with the same IK approach.
  - Spähfalke is a light recon strider with amphibious seals.
  - Kaiserstuhl is a command walker with antenna and ECM gear.
  - Siegebreaker is a super-heavy dreadnought carrying a 210mm howitzer and quad flak.
- Sprites are drawn facing **right**. The side on the right of the screen uses a mirrored copy.

### 5.3 Animation: idle and attacks

**Idle.** A six-frame knee bend. The body offset (forward lean, sink) cycles roughly through `[0,0] [0,1] [1,2] [1,3] [1,2] [0,1]`, and heavier chassis sink deeper and cycle more slowly. Brenner uses a max sink of 4 at about 210 ms per frame, against Sturmjäger's 3 at about 150 ms. On every frame the legs are re-solved with two-bone IK:

- the hips move with the body
- the ankles stay fixed on planted feet
- the knee always bends toward the facing direction
- the front-leg piston stretches between thigh and shin

Exhaust smoke rises from the stack tops and follows the body.

**Weapon attack structure.** This applies to BALLISTIC, ARTILLERY and THERMAL cards and follows the approved 88mm sequence:

1. The command box closes and the banner shows the card name.
2. A short **external** wind-up. For the 88mm it's a 1 px breech jolt plus the viewport blinking ready. Never show internal loading.
3. **Fire:**
   - muzzle flash, 3 frames with sparks
   - **recoil**: the barrel kicks back about 6 px and the turret about 2 px
   - the body shoves back and down, the IK legs absorb it, and it eases back over about 600 ms
   - muzzle smoke, and a spent casing where it makes sense
4. **Projectile** crosses to the target. The 88mm uses a tracer shell on a slight arc.
5. **Impact:**
   - a white burst, then a fireball, then smoke, with scattering debris
   - the defender **flashes white** (alternating every ~45 ms for ~240 ms)
   - the defender **shakes** sideways (±3 px, decaying over ~500 ms) and sinks on its knees
6. **Damage number** in white with a dark outline, bouncing FF6 style, then the hull gauge drops.
7. The command box returns.

The full 88mm loop takes about 4.6 s in the mockup, which is the reference pacing for one action.

**Per-weapon variety.** Each weapon card gets its own wind-up, projectile and recoil, built from shared effect pieces: flash, smoke, explosion, white flash, shake and numbers. The approved design is the 88mm as drafted. *For the remaining weapons the builder designs the animation.* Suggestions only:

| Card | Suggestion |
|---|---|
| Twin MG-42 Salvo | Tracer stream with many small hits |
| 210mm Siege Howitzer | Tall lob, then a heavy impact |
| Quad Flak-38 Battery | Four-barrel alternating bursts |
| 50mm Rapid Autocannon | Rapid 3-round burst |
| Nebelwerfer Rocket Pod | Salvo of smoking rockets that arc in |
| 105mm StuH Howitzer | Direct-fire heavy shell |
| Thermite Flame Lance | Flame stream with heat shimmer, burning on the target |
| Hydraulic Pile-Bunker | Lunge across the gap, spike strike, return |

### 5.4 Armor and tactical card visuals (decided by the owner)

Every card, weapon or not, gets the **same banner** and plays its animation the same way.

**How these fit fixed damage (owner decisions).** Every `BoutStep` deals damage whatever the card type (§5.5), so three rules apply:

1. **Effect + follow-up shot.** On an ARMOR or TACTICAL step, the card's effect plays first. Then the mech fires a quick follow-up with its basic gun, and that shot carries the step's damage number. The builder decides which gun is "basic" per chassis, for example the first weapon in its deck. The follow-up is a shortened weapon animation: flash, projectile, impact, number.
2. **Defensive effects soften, they never negate.** Ricochet, sidestep and reactive bricks visibly blunt the opponent's *next* hit: sparks, a partial dodge, a brick burst meeting the shell. **The hit still connects and the real number shows. `MISS` never appears.** If the opponent has no later step in this fight, the defensive effect is just the stance or deploy on its own step, with nothing to blunt.
3. **Forward-looking effects are self-contained.** An effect that sets up a shot is paid off inside its own step's follow-up, never by a later card:
   - Elevation Ballistics: the arc is plotted and the follow-up shell flies along it.
   - Optical Rangefinder: the lock is followed by an aimed shot.
   - Command Uplink: the call is followed by a shot with the green buff glow.

   Nothing in this list depends on what the mech plays next.

The table below describes the effect part. Wherever a row says "next incoming" or "next shot", read it through rules 2 and 3.

| Card | Chassis | Visual |
|---|---|---|
| Sloped Krupp Plate | Sturmjäger | **Ricochet.** The mech angles its hull, and the next incoming shell skips off the glacis in a shower of sparks. |
| Ferro-Bunker Bulkhead | Siegebreaker | **Slab drops.** A massive armor slab slams down in front with a dust shockwave and stays as cover for the rest of the fight. |
| Quad Anchor Struts | Spinne | **Outriggers deploy.** Four struts punch into the ground with a dust kick. The mech stays braced low for the rest of the fight and its idle stops bobbing. |
| Reactive Shield Wall | Brenner | **Bricks detonate.** Reactive bricks blow outward and meet the incoming shot mid-air. The spent bricks are gone from the sprite afterwards. |
| Gyro-Flank Thrusters | Spähfalke | **Steam sidestep.** Hip steam jets fire, the mech blurs sideways leaving 2–3 afterimages, and the incoming attack whiffs past. |
| Optical Rangefinder | Spähfalke | **Reticle lock.** Stereo rangefinder arms extend, the lenses glint, and a crosshair slides onto the enemy and snaps to `LOCK`. |
| Elevation Ballistics | Spinne | **Arc plotted.** Analog dials spin in a small CRT inset, then a dotted ballistic arc draws to the target, and the next shot follows it. |
| Enigma ECM Scrambler | Kaiserstuhl | **Static on enemy.** Radio rings pulse from the antenna, and the enemy sprite tears into horizontal glitch lines while its visor flickers. |
| Command Uplink | Kaiserstuhl | **Mast + radio call.** A tall mast telescopes up, a signal ring pulses skyward, a short radio-chatter box appears (e.g. `HQ: FIRE MISSION CONFIRMED`), and the mech glows green. |

"Stays for the rest of the fight" effects (slab, struts, missing bricks) last until the battle screen closes. They don't carry over to the grid.

### 5.5 Playback of a skirmish

- The screen consumes `SkirmishResult` unchanged. `result.steps` holds 6 `BoutStep`s alternating attacker (even index) and defender (odd index), each with:
  - `card_placed`
  - `flipped_slots`
  - `combo_type` (`""`, `OVERMATCH` or `TACTICAL PLUS`)
  - `atk_damage_dealt`: damage to the defender, on attacker steps
  - `def_damage_dealt`: damage to the attacker, on defender steps
- **Each step is one action.**
- **The command box appears only for Coalition actions.** Syndikat actions play FF6-enemy style: no menu, just the banner and the animation. *(Builder-check call.)*
- On a Coalition action, the cursor moves automatically to the row matching the card's category, and the menu returns between actions:

  | Card type | Command row |
  |---|---|
  | BALLISTIC, ARTILLERY, THERMAL | `FIGHT` |
  | ARMOR | `ARMOR` |
  | TACTICAL | `TACTIC` |

  Mapping weapons to `FIGHT` versus `WEAPON` is the builder's call (see §8).
- Then the banner shows `card_placed.card_name`, the card's animation plays, and the step's damage number shows on the opponent.
- **Hull display.** Only the Coalition mech has a HULL gauge, in the stats panel. The Syndikat mech's hull is hidden FF6 style, so its hits show as damage numbers only. *(Builder-check call.)*
  - Every damage number is the step's `atk_damage_dealt` or `def_damage_dealt`, exactly.
  - Before the fight, the gauge equals `atk_armor_before` or `def_armor_before`. After it, the gauge equals `*_armor_after`.
- **Hull reaching 0 before the mech's last step (owner decision): hold at 1.**
  - The visible hull stops at 1, a sliver, while the mech still has steps left. It staggers, sparks and smokes but keeps acting.
  - True 0 and the destruction animation play only at the end of the fight.
  - Damage numbers are always shown in full, even when they exceed the remaining visible hull.
  - The same applies to the hidden Syndikat hull: it shows the stagger and sparks with no gauge.
- **Captures** (`flipped_slots` not empty) are text only: a second banner line or a short CRT ticker such as `OVERMATCH: 1 SYSTEM CAPTURED` or `TACTICAL PLUS OVERLOAD`. The 3×3 board is never shown.
- **End of fight.** A result banner shows `summary_headline` (e.g. `TACTICAL VICTORY (4-2) — GLUT-2 DISLODGED!`). Then the ending plays:
  - **Destroyed mech:** a destruction animation, such as a multi-stage explosion and a collapsing silhouette.
  - **Push-back** (`defender_pushed_back`): the defender staggers and gives ground (it backs off a few px and sinks). It does **not** leave the screen.
  - **Repelled:** the attacker staggers back.

  These endings are deliberately generic. If the push-back has no retreat tile, `Battlefield` later decides between 15 crush damage and an attacker fallback after the screen closes. That stays unchanged, and the grid shows the real outcome. Don't move that logic into the screen. *(Builder-check call.)*

  The grid then performs its existing removal and retreat logic, unchanged.
- **Controls** stay the same as today:
  - Space or Enter skips to the end of the fight.
  - Space or Enter on the result confirms and closes.
  - A speed toggle (1×/2×) is kept.

### 5.6 Placement and backdrop

- **Backdrop** = terrain of the **target (defender) tile**. There's one backdrop per terrain: Open Plain, Transit Road, River Ford, Trench Timber, Fortified City and Mountain Crag. The approved Open Plain is a hazy dawn sky, distant smoke plumes, two hill layers, a fence line, dithered grass bands and craters. The other five are designed by the builder in the same style. Elevation may tint or vary a backdrop, for example more sky and lower hills at 300–400 m. That's the builder's call.
- **Sides.** Engagements always come from the adjacent `from_tile` into `target_tile`, so the gap between the mechs is **fixed**. Side is decided by the screen-space x direction of the approach, using `IsoGridMap.grid_to_screen` (`sx = (x − y)·TILE_W/2`):
  - if the attacker's tile is screen-left of the target, the attacker stands **left** facing right
  - otherwise the attacker stands **right** facing left
  - the defender takes the other side

  Faction doesn't decide side; colour does.
- **Elevation.** When `result.elev_diff ≠ 0`, the higher mech stands higher on screen, a few native px per 100 m. It must stay inside the battle area. The exact offset is the builder's call.
- The player-side stats panel always shows the **Coalition** mech, whether it's attacking or defending. The enemy box always shows the **Syndikat** mech.

### 5.7 Integration

- Add a new battle-screen node, for example `BattleScreen`, that replaces `SkirmishModal` in `UIOverlay`. It keeps the same contract so `Battlefield` and the playtest need little or no change:
  - `start_showdown(result)`
  - `signal resolution_confirmed(result)`
  - `visible`
  - skip and confirm entry points
- `tests/playtest.gd` drives the modal through `bf.ui_overlay.skirmish_modal`, `modal._all_steps_done`, `modal._on_skip_pressed()` and `modal._on_confirm_pressed()`. Keep those names working, or update the playtest equivalently. **The playtest must pass headless**, with the same exit code semantics.
- Headless runs: the screen must work, or at least skip cleanly, with `DisplayServer` headless. Sound already no-ops headless.
- `SkirmishModal.gd` may be deleted once nothing references it, or left unused. That's the builder's call.

## 6. Constraints

- Godot **4.7**, GDScript, Forward Plus. Godot is at `/opt/homebrew/bin/godot`.
- Viewport 1440×900, `canvas_items` stretch. The battle screen renders at 360×225 and scales by an integer 4×.
- Art must be generated by a script checked into the repo (e.g. `tools/battle_sprites/`) and exported as PNGs under `assets/battle/`:
  - mechs: per chassis × faction × pose/frame, or per-part sheets if the builder rigs in-engine
  - effects
  - backdrops
  - fonts if needed

  Re-running the generator must reproduce the committed PNGs.
- **How the leg IK runs** is the builder's call:
  - **Pre-baked:** every needed pose rendered to frames by the generator.
  - **Runtime:** parts as sprites rigged in Godot with IK.

  Either way the articulation must look like the mockup. The mockup pre-bakes, because each pose rasterizes as one piece so outlines and shading stay clean.
- The main checkout has untracked `assets/music/` and `tools/music/` that aren't part of this branch. New files go under `assets/battle/` and `tools/battle_sprites/` so nothing collides when they meet.
- `.superpowers/` (brainstorm scratch) and `.playwright-mcp/` must be gitignored.

## 7. Preview scene

Add a dev scene, e.g. `tests/BattleSpritePreview.tscn` or `scenes/dev/…`, that shows:

- every chassis in both palettes
- the idle, plus a trigger for each card animation
- each backdrop

It's for owner review of the new designs, and it isn't reachable from the main menu.

## 8. Left to the builder

- Designs of the four new chassis and five new backdrops, within §5.2 and §5.6.
- Animations of the eight weapons other than the 88mm, within §5.3.
- Destruction, push-back and withdrawal animations.
- Exact pacing per action (88mm ≈ 4.6 s is the reference) and the 2× speed timings.
- Generator language and tooling. Python with Pillow, a Godot `@tool` script, or Node with canvas are all fine as long as it's committed and deterministic.
- Whether weapons map to `FIGHT` or `WEAPON` in the auto-cursor. `FIGHT` could be reserved for the follow-up's basic attack.
- Bitmap font choice.
- Sound cues, reusing existing `SoundManager` sounds: `cannon_fire`, `card_flip`, `mech_destroy`, `ui_confirm` and so on.
- Removing or keeping `SkirmishModal.gd`.

## 9. Resolved during review

Owner decisions:

- Non-weapon steps show their effect and then a follow-up shot that carries the damage.
- Defensive effects soften the next hit but never negate it.
- Forward-looking effects are self-contained within their own step.
- Hull holds at 1 until the end of the fight.

My calls during the builder check, which the owner may override:

- The command box appears only on Coalition actions.
- The enemy hull is hidden and shown through damage numbers only.
- The enemy box shows the battleground tile.
- Push-back and repelled endings are generic and stay on screen.
- Headlines wrap or use short callsigns.

## 10. Open

- **Base branch.** This worktree was cut from `main` (`036276b`). The working branch `fix/restore-turn-end-victory` is four commits ahead, and some of those commits touch `Battlefield.gd` (retreat snap callbacks, AI upkeep). The plan should rebase onto it, or wait for it to merge, before touching `Battlefield`, `UIOverlay` or the playtest.
