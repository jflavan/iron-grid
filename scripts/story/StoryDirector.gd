class_name StoryDirector
extends RefCounted

## One story mission's script at run time: which triggers have fired, and the mission's own win /
## loss rules. Node-free: Battlefield polls it at the points where the plot may cut in (turn start,
## before and after a skirmish, after a move) and plays what it returns.
##
## Trigger: {"on": kind, ..., "lines": [dialog lines], "effects": [effect dicts]}; each fires once,
## in script order. Kinds:
##   "turn"      {"turn": n}                      start of the player's phase on turn n (or later)
##   "skirmish"  {"pilot": id, "vs": id (opt)}    that pilot is about to fight (optionally: that foe)
##   "down"      {"pilot": id}                    that pilot's walker was wrecked
##   "hull"      {"pilot": id, "below": pct}      that pilot's hull is under pct% (and it still stands)
##   "capture"   {"pos": Vector2i, "owner": f}    that objective is now held by faction f
##   "foes_left" {"count": n}                     n or fewer Syndikat walkers remain
## Optional on any trigger: "if_fired": id / "unless_fired": id (another trigger's "id") and "id".
## Effects are applied by Battlefield (see Battlefield._apply_story_effect).

var mission: Dictionary
var _fired: Dictionary = {}   # trigger index -> true
var _fired_ids: Dictionary = {}
## Set by a "win" / "lose" effect: {"winner", "reason", "title"}; verdict() reports it first.
var forced: Dictionary = {}
## Coalition story pilots wrecked this mission (their later trigger lines are dropped).
var lost: Dictionary = {}

func _init(p_mission: Dictionary) -> void:
	mission = p_mission

## Triggers that fire now, marked as fired. `ctx` carries the event facts: "turn" (int, only at the
## start of a player phase), "skirmish" ([attacker pilot, defender pilot], before a battle),
## "down" ([pilot ids] wrecked by the battle just resolved).
func poll(ctx: Dictionary, units: UnitContainer, grid: IsoGridMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var triggers: Array = mission.get("triggers", [])
	# "if_fired" looks at what had fired before this poll: a reaction to a beat waits for the next
	# poll whichever way the beat was set off. "unless_fired" sees this poll's ids too, so two
	# alternative triggers for one beat can never both fire.
	var before: Dictionary = _fired_ids.duplicate()
	for i in triggers.size():
		if _fired.has(i):
			continue
		var t: Dictionary = triggers[i]
		if t.has("if_fired") and not before.has(t["if_fired"]):
			continue
		if t.has("unless_fired") and _fired_ids.has(t["unless_fired"]):
			continue
		if _matches(t, ctx, units, grid):
			_fired[i] = true
			if t.has("id"):
				_fired_ids[t["id"]] = true
			out.append(t)
	return out

func has_fired(id: String) -> bool:
	return _fired_ids.has(id)

## False while the mission's "win_requires" trigger id has not fired: a victory by the map's rules
## waits for the story beat the debrief depends on. A scripted ending is always allowed.
func win_allowed() -> bool:
	var need: String = str(mission.get("win_requires", ""))
	return need == "" or not forced.is_empty() or has_fired(need)

func _matches(t: Dictionary, ctx: Dictionary, units: UnitContainer, grid: IsoGridMap) -> bool:
	match str(t.get("on", "")):
		"turn":
			return ctx.has("turn") and int(ctx["turn"]) >= int(t.get("turn", 1))
		"skirmish":
			var pair: Array = ctx.get("skirmish", [])
			if not pair.has(t.get("pilot", "")):
				return false
			return not t.has("vs") or pair.has(t["vs"])
		"down":
			return (ctx.get("down", []) as Array).has(t.get("pilot", ""))
		"hull":
			if ctx.has("skirmish"):
				return false   # judged on the state a battle leaves, not on the way into one
			var u := units.unit_of_pilot(str(t.get("pilot", "")))
			return u != null and u.mech_data.get_armor_ratio() * 100.0 < float(t.get("below", 50))
		"capture":
			var td := grid.get_tile(t.get("pos", Vector2i(-1, -1)))
			return td != null and td.controlled_by == int(t.get("owner", 0))
		"foes_left":
			return not ctx.has("skirmish") and units.get_faction_units(MechData.Faction.AI).size() <= int(t.get("count", 0))
	return false

## The mission's own verdict, checked before the map's VictoryRules: a scripted ending, a pilot whose
## loss fails the mission ("lose_if_lost"), or the target whose fall wins it ("win_if_down").
## `down` lists the pilots wrecked since the last check. {} while neither applies.
func verdict(down: Array) -> Dictionary:
	if not forced.is_empty():
		return forced
	for p in mission.get("lose_if_lost", []):
		if down.has(p):
			return {"winner": 1, "reason": "%s was shot down. The operation cannot continue without them." % StoryCast.display_name(p)}
	var target: String = str(mission.get("win_if_down", ""))
	if target != "" and down.has(target):
		return {"winner": 0, "reason": str(mission.get("win_text", "%s has fallen." % StoryCast.display_name(target)))}
	return {}
