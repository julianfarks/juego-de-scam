class_name AIResponse
extends RefCounted
## Valida y limpia lo que devuelve la IA remota antes de que toque el juego.
## La IA no puede: fijar dinero, inventar pagos, dictar números de tarjeta reales,
## ni mover las emociones más allá de unos límites pequeños.

const EMOTIONS := ["neutral", "happy", "joy", "angry", "confused", "surprised", "distrust", "sad"]
const GESTURES := ["", "nod", "shake", "laugh", "point", "head_scratch", "arms_crossed", "angry", "surprised", "think", "hangup"]
const MAX_DELTA := 10.0


static func sanitize_text(t: String, max_len := 360) -> String:
	var s := t.strip_edges()
	# Quita marcas de formato típicas de los modelos
	for m in ["**", "__", "##", "`"]:
		s = s.replace(m, "")
	s = s.replace("\n", " ")
	# Elimina cualquier secuencia larga de dígitos (posibles números de tarjeta/cuenta)
	var re := RegEx.new()
	re.compile("(?:\\d[\\s\\-\\.]?){7,}")
	s = re.sub(s, "[número tachado]", true)
	if s.length() > max_len:
		s = s.substr(0, max_len).rsplit(" ", true, 1)[0] + "…"
	return s


static func validate_chat(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {"ok": false, "error": "Formato inesperado"}
	var reply := sanitize_text(str(data.get("reply", "")))
	if reply.length() < 1:
		return {"ok": false, "error": "Respuesta vacía"}
	var emotion := str(data.get("emotion", "neutral"))
	if not EMOTIONS.has(emotion):
		emotion = "neutral"
	var gesture := str(data.get("gesture", ""))
	if not GESTURES.has(gesture):
		gesture = ""
	var deltas := {}
	var raw: Variant = data.get("deltas", {})
	if raw is Dictionary:
		for k in ConversationRules.KEYS:
			deltas[k] = clampf(float(raw.get(k, 0.0)), -MAX_DELTA, MAX_DELTA)
	var receptive := clampf(float(data.get("receptive", 0.0)), 0.0, 1.0)
	return {
		"ok": true, "reply": reply, "emotion": emotion, "gesture": gesture, "deltas": deltas,
		"receptive": receptive, "hang_up": bool(data.get("wants_to_hang_up", false)),
		"source": "remote",
	}
