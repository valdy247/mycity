extends RefCounted
# Cached, small original audio clips; no external assets.
static var sounds: Dictionary = {}
static func cue(kind: String) -> AudioStreamWAV:
	if sounds.has(kind): return sounds[kind] as AudioStreamWAV
	var duration := .40 if kind=="success" else (.19 if kind=="step" else .30)
	var count := int(duration*16000)
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	for i in range(count):
		var t := float(i)/16000.0
		var p := t/duration
		var envelope := sin(PI*p)*(1.0-p)
		var frequency := 74.0 if kind=="step" else (104.0 if kind=="warning" else (523.25 if p<.45 else 659.25))
		var signal_value := sin(TAU*t*frequency)*envelope
		if kind=="step": signal_value += (float(posmod(i*73,257))/128.0-1.0)*envelope*.20
		bytes.encode_s16(i*2,roundi(signal_value*3000.0))
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 16000
	audio.data = bytes
	sounds[kind] = audio
	return audio

static func escape_progress(initial: float,remaining: float) -> float:
	if initial<=.01: return 0.0
	return clampf(1.0-maxf(0.0,remaining)/initial,0.0,1.0)

static func rider_lean(speed: float,turn: float) -> float:
	return clampf(-turn,-1.0,1.0)*clampf(absf(speed)/10.0,0.0,1.0)*.12
