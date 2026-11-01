class_name StrikePlan
extends RefCounted

## Why a selected walker can (or cannot) strike an enemy tile, built by IsoGridMap.compute_strike_plan.
## An attack is a move onto the enemy's tile, so the strike costs the cheapest path to a launch tile
## (one of the enemy's neighbours) plus the step onto the enemy: terrain + chassis + climb.
## The HUD's OUT OF REACH box and the Comms Log line are both written from this object.

enum { REACHABLE, IN_STRIKING_DISTANCE, BEYOND_RANGE, NO_APPROACH }
enum { ADV_NONE, ADV_IMPOSSIBLE, ADV_WAIT_HERE, ADV_MOVE_TO, ADV_WAIT, ADV_MULTI_TURN }

var severity: int = NO_APPROACH
var needs: int = 0                    # cheapest fuel for the whole strike (path + final step)
var have: int = 0                     # attacker's fuel now
var path_fuel: int = 0                # fuel to reach the chosen launch tile
var launch: Vector2i = Vector2i(-1, -1)
var step: Dictionary = {}             # MechData.get_step_fuel_breakdown of launch -> enemy
var advice: int = ADV_NONE
var move_to: Vector2i = Vector2i(-1, -1)  # the launch tile ADV_MOVE_TO points at

## The strike's fuel terms, e.g. ["PATH 2", "MTN 5", "HEAVY 1", "CLIMB 1"]: they add up to needs.
func breakdown_terms() -> PackedStringArray:
	var parts: PackedStringArray = []
	if step.is_empty():
		return parts
	if path_fuel > 0:
		parts.append("PATH %d" % path_fuel)
	parts.append("%s %d" % [step["terrain"], int(step["base"])])
	var ch: int = int(step["chassis"])
	if ch != 0:
		var label: String = step["chassis_label"] if step["chassis_label"] != "" else "CHASSIS"
		parts.append("%s %d" % [label, ch] if ch > 0 else "%s -%d" % [label, -ch])
	if int(step["climb"]) > 0:
		parts.append("CLIMB %d" % int(step["climb"]))
	return parts

## "PATH 2 + MTN 5 + HEAVY 1 + CLIMB 1".
func breakdown_text(sep: String = " + ") -> String:
	return sep.join(breakdown_terms())

func advice_text() -> String:
	match advice:
		ADV_IMPOSSIBLE:
			return "THIS CHASSIS CAN'T CLIMB THERE"
		ADV_WAIT_HERE:
			return "WAIT/REFUEL HERE, STRIKE NEXT TURN IF IT HOLDS"
		ADV_MOVE_TO:
			return "MOVE TO %d,%d, STRIKE NEXT TURN IF IT HOLDS" % [move_to.x, move_to.y]
		ADV_WAIT:
			return "WAIT/REFUEL, STRIKE NEXT TURN IF IT HOLDS"
		ADV_MULTI_TURN:
			return "REFUEL FIRST: TAKES 2+ TURNS"
	return ""

## Body of the HUD box (under its OUT OF REACH title) for IN_STRIKING_DISTANCE, or the single quiet
## line for BEYOND_RANGE / NO_APPROACH, wrapped to max_px. The breakdown wraps between terms only,
## so "MTN" never ends up on a different line from its "5". Empty when the enemy is reachable.
func panel_lines(max_px: float = INF) -> PackedStringArray:
	var out := PackedStringArray()
	match severity:
		IN_STRIKING_DISTANCE:
			out.append_array(_wrap("NEEDS %dF, HAVE %dF" % [needs, have], max_px))
			var line := ""
			for term in breakdown_terms():
				var candidate := term if line == "" else line + " +" + term
				if line != "" and PixelFont.text_width(CrtUI.sanitize(candidate)) > max_px:
					out.append(line)
					line = "+" + term
				else:
					line = candidate
			out.append(line)
			out.append_array(_wrap(advice_text(), max_px))
		BEYOND_RANGE:
			out.append_array(_wrap("BEYOND MOVE RANGE (NEEDS %dF)" % needs, max_px))
		NO_APPROACH:
			out.append_array(_wrap("NO OPEN APPROACH TILE", max_px))
	return out

static func _wrap(s: String, max_px: float) -> PackedStringArray:
	return PackedStringArray([CrtUI.sanitize(s)]) if max_px == INF else CrtUI.wrap_lines(s, max_px)

func log_line(attacker_callsign: String, target_callsign: String) -> String:
	return "%s CANNOT REACH %s: STRIKE NEEDS %dF (%s), %dF LEFT." % [
		attacker_callsign, target_callsign, needs, breakdown_text(" +"), have
	]
