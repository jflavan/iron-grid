class_name StoryProgress
extends RefCounted

## Campaign progress on disk: how many chapters the player has cleared. JSON under user:// with a
## version field; an unreadable or newer-than-known file reads as a fresh campaign.

const SAVE_PATH := "user://story_save.json"
const VERSION := 1

## Overridable so tests never touch the player's save.
static var path: String = SAVE_PATH

## Index of the first chapter not yet cleared (0 = fresh campaign; chapters().size() = finished).
static func cleared() -> int:
	if not FileAccess.file_exists(path):
		return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("StoryProgress: %s is not a valid save; starting a fresh campaign" % path)
		return 0
	var data: Dictionary = _migrate(parsed)
	return clampi(int(data.get("cleared", 0)), 0, StoryCampaign.chapters().size())

## Records that chapter `index` was cleared (never lowers the stored progress).
static func mark_cleared(index: int) -> void:
	_write(maxi(cleared(), index + 1))

static func reset() -> void:
	_write(0)

static func _write(value: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("StoryProgress: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify({"version": VERSION, "cleared": value}))
	f.close()

## Brings an older save up to VERSION one step at a time (nothing to migrate yet).
static func _migrate(data: Dictionary) -> Dictionary:
	if int(data.get("version", 0)) > VERSION:
		push_warning("StoryProgress: save is from a newer build; reading what this build understands")
	return data
