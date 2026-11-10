extends Node

## Procedural Dieselpunk Audio Synthesizer
## Generates crisp retro/industrial WAV samples in memory so the game has full audio feedback without external assets.

const SAMPLE_RATE: int = 22050
var _players: Array[AudioStreamPlayer] = []
var _samples: Dictionary = {}
var muted: bool = false
var _headless: bool = false
var _steal_idx: int = 0   # voice to cut when all players are busy (round-robin: the oldest-started)

func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	if not _headless:   # headless never plays: skip synthesising ~10 waveforms
		_generate_all_samples()

func _generate_all_samples() -> void:
	_samples["ui_click"] = _make_tone_burst(680.0, 320.0, 0.055, 0.25, "square")
	_samples["ui_confirm"] = _make_dual_beep(520.0, 780.0, 0.11, 0.3)
	_samples["ui_cancel"] = _make_dual_beep(420.0, 260.0, 0.12, 0.3)
	_samples["mech_step"] = _make_mech_stomp(0.14)
	_samples["radar_lock"] = _make_dual_beep(880.0, 1320.0, 0.16, 0.35)
	_samples["tech_activate"] = _make_tone_burst(340.0, 140.0, 0.09, 0.4, "saw")
	_samples["buff_up"] = _make_dual_beep(600.0, 960.0, 0.13, 0.38)
	_samples["cannon_fire"] = _make_explosion(0.28, 190.0)
	_samples["mech_destroy"] = _make_explosion(0.55, 95.0)
	_samples["type_blip"] = _make_tone_burst(980.0, 760.0, 0.016, 0.10, "square")   # story dialog typewriter
	_samples["phase_shift"] = _make_dual_beep(330.0, 495.0, 0.22, 0.3)

func play(sfx_name: String, pitch_scale: float = 1.0) -> void:
	if muted or _headless:
		return
	if not _samples.has(sfx_name):
		push_warning("SoundManager: unknown sample '%s'" % sfx_name)
		return
	for p in _players:
		if not p.playing:
			p.stream = _samples[sfx_name]
			p.pitch_scale = pitch_scale
			p.play()
			return
	# Every voice busy: steal them in turn rather than always cutting voice 0.
	var p := _players[_steal_idx]
	_steal_idx = (_steal_idx + 1) % _players.size()
	p.stream = _samples[sfx_name]
	p.pitch_scale = pitch_scale
	p.play()

func _make_tone_burst(start_freq: float, end_freq: float, duration: float, amp: float, wave: String) -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in range(count):
		var t := float(i) / float(count)
		var freq := lerpf(start_freq, end_freq, t)
		phase += freq / float(SAMPLE_RATE)
		var env := (1.0 - t) * (1.0 - t)
		var s := 0.0
		if wave == "square":
			s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		elif wave == "saw":
			s = fmod(phase, 1.0) * 2.0 - 1.0
		else:
			s = sin(phase * TAU)
		var val := int(clampf(s * env * amp, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = data
	return wav

func _make_dual_beep(freq1: float, freq2: float, duration: float, amp: float) -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in range(count):
		var t := float(i) / float(count)
		var freq := freq1 if t < 0.48 else freq2
		phase += freq / float(SAMPLE_RATE)
		var env := 1.0 - fmod(t * 2.0, 1.0) * 0.6
		var s := sin(phase * TAU) * 0.7 + (1.0 if fmod(phase, 1.0) < 0.5 else -1.0) * 0.3
		var val := int(clampf(s * env * amp, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = data
	return wav

func _make_mech_stomp(duration: float) -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var phase := 0.0
	for i in range(count):
		var t := float(i) / float(count)
		var freq := lerpf(110.0, 38.0, t)
		phase += freq / float(SAMPLE_RATE)
		var env := pow(1.0 - t, 1.8)
		var thud := sin(phase * TAU) * 0.75
		var hiss := rng.randf_range(-1.0, 1.0) * 0.25 * (1.0 - t)
		var val := int(clampf((thud + hiss) * env * 0.5, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = data
	return wav

func _make_explosion(duration: float, start_freq: float) -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4200
	var phase := 0.0
	var prev := 0.0
	for i in range(count):
		var t := float(i) / float(count)
		var freq := lerpf(start_freq, 28.0, pow(t, 0.5))
		phase += freq / float(SAMPLE_RATE)
		var env := pow(1.0 - t, 1.4)
		var raw_noise := rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, raw_noise, 0.35)
		var boom := sin(phase * TAU) * 0.55 + prev * 0.65
		var val := int(clampf(boom * env * 0.55, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, val)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = data
	return wav
