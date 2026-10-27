extends Node
## Cliente del backend de IA. El APK no contiene ninguna clave de proveedor: solo la
## URL del servidor y un código de acceso que el jugador escribe en Ajustes.
## Si el servidor no está configurado o falla, el juego usa el diálogo local y lo indica.

signal status_changed(status: String)   # unconfigured | connecting | online | offline | error

const TIMEOUT_CHAT := 14.0
const TIMEOUT_STT := 20.0
const TIMEOUT_TTS := 15.0
const APP_VERSION := "0.1.0"

var status := "unconfigured"
var last_error := ""
var token := ""
var token_expiry := 0.0
var device_id := ""
var usage := {"requests": 0, "input_tokens": 0, "output_tokens": 0, "stt_seconds": 0.0, "tts_chars": 0}
var _active: Dictionary = {}   # id -> HTTPRequest
var _seq := 0
var _offline_until := 0.0


func _ready() -> void:
	device_id = _load_device_id()
	_refresh_status()
	Settings.changed.connect(func(k: String) -> void:
		if k in ["backend_url", "access_code"]:
			token = ""
			_offline_until = 0.0
			_refresh_status())


func _load_device_id() -> String:
	var p := "user://device.id"
	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		if f:
			var id := f.get_as_text().strip_edges()
			if id.length() >= 16:
				return id
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var id := ""
	for i in 32:
		id += "0123456789abcdef"[rng.randi() % 16]
	var fw := FileAccess.open(p, FileAccess.WRITE)
	if fw:
		fw.store_string(id)
	return id


func _refresh_status() -> void:
	if not Settings.is_ai_configured():
		_set_status("unconfigured")
	elif status == "unconfigured":
		_set_status("offline" if token == "" else "online")


func _set_status(s: String) -> void:
	if s != status:
		status = s
		status_changed.emit(s)


func base_url() -> String:
	return str(Settings.get_value("backend_url")).rstrip("/")


## ¿Intentamos IA remota en este turno? (si falló hace poco, esperamos un poco)
func remote_available() -> bool:
	if not Settings.is_ai_configured():
		return false
	return Time.get_ticks_msec() / 1000.0 >= _offline_until


func _mark_failure(err: String) -> void:
	last_error = err
	_offline_until = Time.get_ticks_msec() / 1000.0 + 25.0
	_set_status("offline")


func _request(method: int, path: String, body: Variant, timeout: float, auth := true, raw_body: PackedByteArray = PackedByteArray(), content_type := "application/json") -> Dictionary:
	_seq += 1
	var id := _seq
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.use_threads = true
	add_child(http)
	_active[id] = http
	var headers := PackedStringArray(["Content-Type: " + content_type, "X-App-Version: " + APP_VERSION])
	if auth and token != "":
		headers.append("Authorization: Bearer " + token)
	var err: int
	if raw_body.size() > 0:
		err = http.request_raw(base_url() + path, headers, method, raw_body)
	else:
		err = http.request(base_url() + path, headers, method, "" if body == null else JSON.stringify(body))
	if err != OK:
		_active.erase(id)
		http.queue_free()
		return {"ok": false, "error": "No se pudo iniciar la petición (%d)" % err, "code": 0}
	var res: Array = await http.request_completed
	_active.erase(id)
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var resp_headers: PackedStringArray = res[2]
	var bytes: PackedByteArray = res[3]
	if result == HTTPRequest.RESULT_REQUEST_FAILED and code == 0 and bytes.is_empty() and not _cancelled.is_empty() and _cancelled.has(id):
		_cancelled.erase(id)
		return {"ok": false, "error": "cancelado", "code": 0, "cancelled": true}
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": _result_text(result), "code": code}
	var ctype := ""
	for h in resp_headers:
		if h.to_lower().begins_with("content-type:"):
			ctype = h.substr(13).strip_edges().to_lower()
	if code < 200 or code >= 300:
		var msg := bytes.get_string_from_utf8().substr(0, 200)
		return {"ok": false, "error": "HTTP %d: %s" % [code, msg], "code": code}
	if ctype.begins_with("application/json"):
		var json := JSON.new()
		if json.parse(bytes.get_string_from_utf8()) != OK:
			return {"ok": false, "error": "Respuesta JSON inválida", "code": code}
		return {"ok": true, "data": json.data, "code": code}
	return {"ok": true, "bytes": bytes, "content_type": ctype, "code": code}


var _cancelled: Dictionary = {}


func cancel_all() -> void:
	for id in _active.keys():
		var http: HTTPRequest = _active[id]
		if is_instance_valid(http):
			_cancelled[id] = true
			http.cancel_request()
			http.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())


func _result_text(r: int) -> String:
	match r:
		HTTPRequest.RESULT_TIMEOUT:
			return "Tiempo de espera agotado"
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE:
			return "Sin conexión con el servidor"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Error de certificado TLS"
	return "Error de red (%d)" % r


func ensure_session() -> bool:
	if token != "" and Time.get_unix_time_from_system() < token_expiry - 30:
		return true
	_set_status("connecting")
	var r := await _request(HTTPClient.METHOD_POST, "/v1/session", {
		"device_id": device_id, "access_code": str(Settings.get_value("access_code")), "app_version": APP_VERSION,
	}, 10.0, false)
	if not r["ok"] or not (r.get("data") is Dictionary) or not r["data"].has("token"):
		_mark_failure(r.get("error", "Sesión rechazada"))
		return false
	token = str(r["data"]["token"])
	token_expiry = Time.get_unix_time_from_system() + float(r["data"].get("expires_in", 3600))
	_set_status("online")
	return true


func health() -> Dictionary:
	if not Settings.is_ai_configured():
		return {"ok": false, "error": "Servidor no configurado"}
	var r := await _request(HTTPClient.METHOD_GET, "/health", null, 8.0, false)
	if r["ok"]:
		var ok_sess := await ensure_session()
		r["session"] = ok_sess
	else:
		_mark_failure(r["error"])
	return r


func _authed(method: int, path: String, body: Variant, timeout: float, raw := PackedByteArray(), ctype := "application/json") -> Dictionary:
	if not await ensure_session():
		return {"ok": false, "error": last_error}
	var r := await _request(method, path, body, timeout, true, raw, ctype)
	if not r["ok"] and int(r.get("code", 0)) == 401:
		token = ""
		if await ensure_session():
			r = await _request(method, path, body, timeout, true, raw, ctype)
	if not r["ok"] and not r.get("cancelled", false):
		if int(r.get("code", 0)) == 0 or int(r.get("code", 0)) >= 500:
			_mark_failure(r["error"])
		else:
			last_error = r["error"]
	return r


## Turno de conversación. Devuelve {ok, reply, emotion, gesture, deltas, receptive, hang_up}
func chat(payload: Dictionary) -> Dictionary:
	usage["requests"] += 1
	var r := await _authed(HTTPClient.METHOD_POST, "/v1/chat", payload, TIMEOUT_CHAT)
	if not r["ok"]:
		return r
	var v := AIResponse.validate_chat(r.get("data", {}))
	if v["ok"]:
		var u: Dictionary = r["data"].get("usage", {})
		usage["input_tokens"] += int(u.get("input_tokens", 0))
		usage["output_tokens"] += int(u.get("output_tokens", 0))
	return v


func transcribe(wav_bytes: PackedByteArray, language := "es") -> Dictionary:
	var boundary := "----teletimo%d" % randi()
	var body := PackedByteArray()
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\n%s\r\n" % [boundary, language]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voz.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % boundary).to_utf8_buffer())
	body.append_array(wav_bytes)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var r := await _authed(HTTPClient.METHOD_POST, "/v1/stt", null, TIMEOUT_STT, body, "multipart/form-data; boundary=" + boundary)
	if not r["ok"]:
		return r
	var text := str(r.get("data", {}).get("text", "")).strip_edges()
	usage["stt_seconds"] += wav_bytes.size() / 32000.0
	return {"ok": text != "", "text": text.substr(0, 600), "error": "" if text != "" else "No se entendió nada"}


func synthesize(text: String, voice: String, instructions: String) -> Dictionary:
	usage["tts_chars"] += text.length()
	var r := await _authed(HTTPClient.METHOD_POST, "/v1/tts", {"text": text.substr(0, 500), "voice": voice, "instructions": instructions}, TIMEOUT_TTS)
	if not r["ok"]:
		return r
	if not r.has("bytes") or r["bytes"].size() < 100:
		return {"ok": false, "error": "Audio vacío"}
	return {"ok": true, "bytes": r["bytes"], "content_type": r.get("content_type", "")}


func boss_comment(stats: Dictionary) -> Dictionary:
	var r := await _authed(HTTPClient.METHOD_POST, "/v1/boss", {"stats": stats, "language": Loc.lang}, TIMEOUT_CHAT)
	if not r["ok"]:
		return r
	var txt := AIResponse.sanitize_text(str(r.get("data", {}).get("comment", "")), 420)
	return {"ok": txt != "", "comment": txt}
