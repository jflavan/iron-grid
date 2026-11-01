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

## "PATH 2 + MTN 5 + HEAVY 1 + CLIMB 1": the terms always add up to needs.
func breakdown_text(sep: String = " + ") -> String:
	if step.is_empty():
		return ""
	var parts: PackedStringArray = []
	if path_fuel > 0:
		parts.append("PATH %d" % path_fuel)
	parts.append("%s %d" % [step["terrain"], int(step["base"])])
	if int(step["chassis"]) != 0:
		var label: String = step["chassis_label"] if step["chassis_label"] != "" else "CHASSIS"
		parts.append("%s %d" % [label, int(step["chassis"])] if int(step["chassis"]) > 0 else "%s -%d" % [label, -int(step["chassis"])])
	if int(step["climb"]) > 0:
		parts.append("CLIMB %d" % int(step["climb"]))
	return sep.join(parts)

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
## line for BEYOND_RANGE / NO_APPROACH. Empty when the enemy is reachable.
func panel_lines() -> PackedStringArray:
	match severity:
		IN_STRIKING_DISTANCE:
			return PackedStringArray(["STRIKE NEEDS %dF, YOU HAVE %dF" % [needs, have], breakdown_text(), advice_text()])
		BEYOND_RANGE:
			return PackedStringArray(["BEYOND MOVE RANGE (NEEDS %dF)" % needs])
		NO_APPROACH:
			return PackedStringArray(["NO OPEN APPROACH TILE"])
	return PackedStringArray()

func log_line(attacker_callsign: String, target_callsign: String) -> String:
	return "%s CANNOT REACH %s: STRIKE NEEDS %dF (%s), %dF LEFT." % [
		attacker_callsign, target_callsign, needs, breakdown_text(" +"), have
	]
