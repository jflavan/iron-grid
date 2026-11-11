extends Node

## Background music. One track at a time, crossfaded on change; asking for the track that is
## already playing does nothing, so a scene change inside the same mood never restarts it.
## Tracks are `assets/music/<id>.ogg` (ids in MusicCues). A track that reaches its last seconds
## starts again underneath its own ending, so pieces need no exact loop point. M mutes / unmutes the music;
## the choice is kept in user://settings.cfg.

const BUS := "Music"
const BUS_DB := -5.0          # under the synthesised SFX, which play at -8 dB on Master
const FADE := 1.2
const LOOP_OVERLAP := 3.5     # seconds of a track's ending that play over its restart
const SILENT_DB := -60.0
const SETTINGS_PATH := "user://settings.cfg"

var current: String = ""      # the id asked for last ("" = silence), also when headless or muted
var muted: bool = false

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _fades: Array = [null, null]   # one Tween per player
var _headless: bool = false
var _missing: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"
	if _headless:
		return
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_volume_db(idx, BUS_DB)
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		muted = bool(cfg.get_value("audio", "music_muted", false))
	_apply_mute()

## Crossfades to track `id`; "" fades to silence.
func play(id: String, fade: float = FADE) -> void:
	if id == current:
		return
	current = id
	if _headless:
		return
	_start(_load(id), fade)

func _process(_delta: float) -> void:
	if _headless or current == "":
		return
	var p := _players[_active]
	if p.playing and p.stream != null:
		var length: float = p.stream.get_length()
		if length > LOOP_OVERLAP * 4.0 and length - p.get_playback_position() <= LOOP_OVERLAP:
			_start(p.stream, LOOP_OVERLAP)
	elif p.stream != null:
		_start(p.stream, 0.0)   # too short to overlap: it ended, so start it again

## Fades the active player out and brings `stream` in on the other one.
func _start(stream: AudioStream, fade: float) -> void:
	_fade(_active, SILENT_DB, fade, true)
	if stream == null:
		return
	_active = 1 - _active
	var p := _players[_active]
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play()
	_fade(_active, 0.0, fade, false)

func stop(fade: float = FADE) -> void:
	play("", fade)

func set_muted(value: bool) -> void:
	muted = value
	if _headless:
		return
	_apply_mute()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music_muted", muted)
	cfg.save(SETTINGS_PATH)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		set_muted(not muted)

func _apply_mute() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS), muted)

func _load(id: String) -> AudioStream:
	if id == "" or _missing.has(id):
		return null
	var p := MusicCues.path(id)
	if not ResourceLoader.exists(p):
		_missing[id] = true
		push_warning("MusicManager: no file for track '%s' (%s)" % [id, p])
		return null
	return load(p)

func _fade(i: int, to_db: float, time: float, stop_after: bool) -> void:
	var p := _players[i]
	if _fades[i] != null:
		_fades[i].kill()
	if not p.playing:
		_fades[i] = null
		return
	var tw := create_tween()
	_fades[i] = tw
	tw.tween_property(p, "volume_db", to_db, maxf(time, 0.01))
	if stop_after:
		tw.tween_callback(p.stop)
