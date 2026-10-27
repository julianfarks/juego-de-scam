class_name Synth
extends RefCounted
## Sintetizador procedural: genera todos los efectos y la música del juego en
## tiempo de ejecución (sin recursos de audio externos ni con derechos de autor).

const RATE := 22050


static func _to_wav(samples: PackedFloat32Array, rate: int = RATE, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		# Unas muestras antes del final: con loop_end == longitud, el mezclador de
		# Android leía fuera del búfer al interpolar y la app se cerraba (SIGSEGV en
		# el hilo AudioTrack; detectado en el emulador por bisección).
		w.loop_end = maxi(0, samples.size() - 16)
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


static func _env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	return exp(-(t - attack) / maxf(decay, 0.0001))


static func tone(freqs: Array, seconds: float, attack := 0.005, decay := 0.2, wave := "sine", vol := 0.5) -> AudioStreamWAV:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		var s := 0.0
		for f in freqs:
			var ph := fmod(t * float(f), 1.0)
			match wave:
				"square":
					s += 1.0 if ph < 0.5 else -1.0
				"saw":
					s += ph * 2.0 - 1.0
				"tri":
					s += 4.0 * absf(ph - 0.5) - 1.0
				_:
					s += sin(TAU * ph)
		b[i] = s / freqs.size() * _env(t, attack, decay) * vol
	return _to_wav(b)


static func noise_burst(seconds: float, decay: float, lowpass := 0.5, vol := 0.5, seed_v := 1) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var b := _buf(seconds)
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y = lerpf(y, rng.randf_range(-1.0, 1.0), lowpass)
		b[i] = y * _env(t, 0.001, decay) * vol
	return _to_wav(b)


static func phone_ring() -> AudioStreamWAV:
	var b := _buf(1.6)
	for i in b.size():
		var t := float(i) / RATE
		var on := (t < 0.45) or (t > 0.6 and t < 1.05)
		if not on:
			continue
		var trill: float = 0.6 + 0.4 * sign(sin(TAU * 20.0 * t))
		b[i] = (sin(TAU * 440.0 * t) + sin(TAU * 480.0 * t)) * 0.22 * trill
	return _to_wav(b)


static func sweep(f0: float, f1: float, seconds: float, wave := "sine", vol := 0.45) -> AudioStreamWAV:
	var b := _buf(seconds)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := t / seconds
		var f := lerpf(f0, f1, k)
		ph = fmod(ph + f / RATE, 1.0)
		var s := sin(TAU * ph) if wave == "sine" else (ph * 2.0 - 1.0)
		b[i] = s * vol * (1.0 - k) * minf(1.0, t * 80.0)
	return _to_wav(b)


static func wah_wah() -> AudioStreamWAV:
	var notes := [233.0, 220.0, 207.0, 185.0]
	var durs := [0.35, 0.35, 0.35, 0.9]
	var total := 0.0
	for d in durs:
		total += d
	var b := _buf(total)
	var start := 0.0
	var ph := 0.0
	var i0 := 0
	for n in notes.size():
		var len_s: float = durs[n]
		var count := int(len_s * RATE)
		for j in count:
			var t := float(j) / RATE
			var vib := 1.0 + (0.02 * sin(TAU * 6.0 * t) if n == 3 else 0.0)
			ph = fmod(ph + notes[n] * vib / RATE, 1.0)
			var s := (ph * 2.0 - 1.0) * 0.7 + sin(TAU * ph) * 0.3
			var wah := 0.4 + 0.6 * absf(sin(PI * t / len_s))
			if i0 + j < b.size():
				b[i0 + j] = s * 0.32 * wah * minf(1.0, (len_s - t) * 20.0)
		i0 += count
		start += len_s
	return _to_wav(b)


static func cash_register() -> AudioStreamWAV:
	var b := _buf(1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in b.size():
		var t := float(i) / RATE
		var s := 0.0
		if t < 0.08:
			s += rng.randf_range(-1, 1) * 0.5 * (1.0 - t / 0.08)
		if t > 0.1:
			var tt := t - 0.1
			s += (sin(TAU * 1568.0 * tt) + sin(TAU * 2093.0 * tt) * 0.7 + sin(TAU * 2637.0 * tt) * 0.4) * exp(-tt * 4.0) * 0.3
		b[i] = s
	return _to_wav(b)


static func applause(seconds := 1.6) -> AudioStreamWAV:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var claps := []
	for c in int(seconds * 45):
		claps.append(rng.randf_range(0.0, seconds - 0.05))
	for c in claps:
		var st := int(float(c) * RATE)
		var amp := rng.randf_range(0.15, 0.35)
		for j in 260:
			if st + j < b.size():
				b[st + j] += rng.randf_range(-1, 1) * amp * exp(-float(j) / 60.0)
	for i in b.size():
		var t := float(i) / RATE
		b[i] *= minf(1.0, t * 6.0) * minf(1.0, (seconds - t) * 2.0)
	return _to_wav(b)


static func laugh() -> AudioStreamWAV:
	var b := _buf(1.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 6:
		var st := int((0.05 + k * 0.2) * RATE)
		var f0 := 260.0 - k * 12.0
		for j in int(0.15 * RATE):
			var t := float(j) / RATE
			var env := sin(PI * t / 0.15)
			var s := sin(TAU * f0 * t) * 0.5 + sin(TAU * f0 * 2.7 * t) * 0.25 + rng.randf_range(-1, 1) * 0.25
			if st + j < b.size():
				b[st + j] = s * env * 0.35
	return _to_wav(b)


static func brown_noise(seconds: float, vol := 0.25, seed_v := 5) -> AudioStreamWAV:
	var b := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var y := 0.0
	for i in b.size():
		y = clampf(y + rng.randf_range(-0.03, 0.03), -1.0, 1.0)
		y *= 0.998
		b[i] = y * vol
	# fundido en los extremos para que el bucle no haga "clic"
	var fade := int(0.05 * RATE)
	for i in fade:
		var k := float(i) / fade
		b[i] *= k
		b[b.size() - 1 - i] *= k
	return _to_wav(b, RATE, true)


## Música: bucle de lounge de oficina generado por acordes (Imaj7-vi7-ii7-V7).
static func music_loop(style: String, bars := 8) -> AudioStreamWAV:
	var bpm := 96.0 if style == "office" else 118.0
	var beat := 60.0 / bpm
	var seconds := bars * 4 * beat
	var b := _buf(seconds)
	var root := 261.63 if style == "office" else 293.66
	var progression := [[0, 4, 7, 11], [9, 12, 16, 19], [2, 5, 9, 12], [7, 11, 14, 17]]
	if style != "office":
		progression = [[0, 4, 7, 12], [5, 9, 12, 16], [7, 11, 14, 19], [5, 9, 12, 17]]
	var bass_pattern := [0, 0, 7, 0] if style == "office" else [0, 7, 0, 7]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 if style == "office" else 77
	var n := b.size()
	var bar_len := 4 * beat
	for i in n:
		var t := float(i) / RATE
		var bar := int(t / bar_len) % progression.size()
		var tb := fmod(t, bar_len)
		var chord: Array = progression[bar]
		var s := 0.0
		# piano eléctrico: acorde en 1 y en el "y" del 2
		var hits := [0.0, beat * 1.5, beat * 3.0] if style == "office" else [0.0, beat, beat * 2.0, beat * 3.0]
		for h in hits:
			var th: float = tb - h
			if th >= 0.0 and th < beat * 1.4:
				var env := exp(-th * 3.2) * minf(1.0, th * 200.0)
				for semi in chord:
					var f := root * pow(2.0, float(semi) / 12.0)
					s += (sin(TAU * f * th) + 0.3 * sin(TAU * f * 2.0 * th)) * env * 0.06
		# bajo
		var bi := int(tb / beat) % 4
		var tbb := fmod(tb, beat)
		var bf := root / 2.0 * pow(2.0, float(int(chord[0]) + int(bass_pattern[bi])) / 12.0)
		s += sin(TAU * bf * tbb) * exp(-tbb * 4.0) * minf(1.0, tbb * 300.0) * 0.22
		# charles
		var eighth := beat / 2.0
		var te := fmod(t, eighth)
		if te < 0.03:
			s += rng.randf_range(-1, 1) * (1.0 - te / 0.03) * (0.05 if int(t / eighth) % 2 == 1 else 0.025)
		# bombo suave en 1 y 3
		var tk := fmod(t, beat * 2.0)
		if tk < 0.12:
			s += sin(TAU * (60.0 + 80.0 * exp(-tk * 30.0)) * tk) * exp(-tk * 18.0) * 0.25
		b[i] = s
	return _to_wav(b, RATE, true)
