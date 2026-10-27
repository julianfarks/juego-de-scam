class_name WavUtil
extends RefCounted
## Conversión de la grabación del micrófono a WAV mono 16 kHz 16 bits (lo que
## aceptan los servicios de transcripción) y cálculo de niveles.


static func to_mono_16k_wav(stream: AudioStreamWAV) -> PackedByteArray:
	var pcm := to_mono_16k_pcm(stream)
	return wrap_wav(pcm, 16000)


static func to_mono_16k_pcm(stream: AudioStreamWAV) -> PackedByteArray:
	var out := PackedByteArray()
	if stream == null or stream.data.is_empty():
		return out
	if stream.format != AudioStreamWAV.FORMAT_16_BITS:
		push_warning("Formato de grabación no soportado")
		return out
	var src := stream.data
	var channels := 2 if stream.stereo else 1
	var frame_bytes := 2 * channels
	var frames := src.size() / frame_bytes
	var src_rate := float(stream.mix_rate)
	var ratio := src_rate / 16000.0
	var out_frames := int(frames / ratio)
	out.resize(out_frames * 2)
	for i in out_frames:
		var pos := int(i * ratio)
		if pos >= frames:
			break
		var base := pos * frame_bytes
		var v := src.decode_s16(base)
		if channels == 2:
			v = (v + src.decode_s16(base + 2)) / 2
		out.encode_s16(i * 2, v)
	return out


static func wrap_wav(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952)        # "RIFF"
	h.encode_u32(4, 36 + pcm.size())
	h.encode_u32(8, 0x45564157)        # "WAVE"
	h.encode_u32(12, 0x20746d66)       # "fmt "
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)                # PCM
	h.encode_u16(22, 1)                # mono
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164)       # "data"
	h.encode_u32(40, pcm.size())
	h.append_array(pcm)
	return h


static func peak(pcm: PackedByteArray) -> float:
	var m := 0
	for i in range(0, pcm.size() - 1, 2):
		m = maxi(m, absi(pcm.decode_s16(i)))
	return float(m) / 32768.0


static func duration_s(pcm16k: PackedByteArray) -> float:
	return pcm16k.size() / 32000.0
