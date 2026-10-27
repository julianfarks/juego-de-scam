class_name Downloader
extends RefCounted
## Descarga HTTP(S) por bloques con reanudación (cabecera Range), seguimiento de
## redirecciones y progreso. Escribe en <destino>.part y lo renombra al terminar.

signal progress(downloaded: int, total: int)

var cancelled := false
var last_error := ""


func cancel() -> void:
	cancelled = true


static func _split_url(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	var rest := url.substr(8 if tls else 7)
	var slash := rest.find("/")
	var host := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var port := 443 if tls else 80
	if ":" in host:
		port = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	return {"tls": tls, "host": host, "port": port, "path": path}


## Descarga url → dest. expected_size > 0 permite comprobar y reanudar.
## Devuelve true si el archivo quedó completo.
func fetch(url: String, dest: String, expected_size: int = -1) -> bool:
	last_error = ""
	if FileAccess.file_exists(dest) and (expected_size <= 0 or FileAccess.get_size(dest) == expected_size):
		return true
	var part := dest + ".part"
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var current := url
	for redirect in 8:
		if cancelled:
			last_error = "cancelado"
			return false
		var have := FileAccess.get_size(part) if FileAccess.file_exists(part) else 0
		if expected_size > 0 and have > expected_size:
			DirAccess.remove_absolute(part)
			have = 0
		var u := _split_url(current)
		var http := HTTPClient.new()
		var opts := TLSOptions.client() if u["tls"] else null
		var err := http.connect_to_host(u["host"], u["port"], opts)
		if err != OK:
			last_error = "No se pudo conectar (%d)" % err
			return false
		var t0 := Time.get_ticks_msec()
		while http.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
			http.poll()
			await Engine.get_main_loop().process_frame
			if Time.get_ticks_msec() - t0 > 20000:
				last_error = "Tiempo de conexión agotado"
				return false
		if http.get_status() != HTTPClient.STATUS_CONNECTED:
			last_error = "Sin conexión a Internet"
			return false
		var headers := PackedStringArray(["User-Agent: TeleTimo3D", "Accept: */*"])
		if have > 0:
			headers.append("Range: bytes=%d-" % have)
		err = http.request(HTTPClient.METHOD_GET, u["path"], headers)
		if err != OK:
			last_error = "Petición fallida (%d)" % err
			return false
		while http.get_status() == HTTPClient.STATUS_REQUESTING:
			http.poll()
			await Engine.get_main_loop().process_frame
		if not http.has_response():
			last_error = "El servidor no respondió"
			return false
		var code := http.get_response_code()
		var rh := http.get_response_headers_as_dictionary()
		var lower := {}
		for k in rh.keys():
			lower[str(k).to_lower()] = rh[k]
		if code in [301, 302, 303, 307, 308]:
			current = str(lower.get("location", ""))
			if current.begins_with("/"):
				current = ("https://" if u["tls"] else "http://") + u["host"] + current
			http.close()
			continue
		if code == 416 and expected_size > 0 and have == expected_size:
			http.close()
			return DirAccess.rename_absolute(part, dest) == OK
		if code != 200 and code != 206:
			last_error = "El servidor respondió %d" % code
			http.close()
			return false
		var f: FileAccess
		if code == 206 and have > 0:
			f = FileAccess.open(part, FileAccess.READ_WRITE)
			f.seek_end()
		else:
			have = 0
			f = FileAccess.open(part, FileAccess.WRITE)
		if f == null:
			last_error = "No se puede escribir en el almacenamiento"
			http.close()
			return false
		var total := expected_size
		if total <= 0:
			total = have + int(lower.get("content-length", "-1"))
		var downloaded := have
		var last_emit := 0
		var stalled_since := Time.get_ticks_msec()
		while http.get_status() == HTTPClient.STATUS_BODY:
			if cancelled:
				f.close()
				http.close()
				last_error = "cancelado"
				return false
			http.poll()
			var chunk := http.read_response_body_chunk()
			if chunk.size() > 0:
				f.store_buffer(chunk)
				downloaded += chunk.size()
				stalled_since = Time.get_ticks_msec()
				if downloaded - last_emit > 262144:
					last_emit = downloaded
					progress.emit(downloaded, total)
			else:
				if Time.get_ticks_msec() - stalled_since > 30000:
					last_error = "La descarga se detuvo (sin datos)"
					break
				await Engine.get_main_loop().process_frame
		f.close()
		http.close()
		progress.emit(downloaded, total)
		if expected_size > 0 and downloaded != expected_size:
			if last_error == "":
				last_error = "Descarga incompleta (%d de %d bytes)" % [downloaded, expected_size]
			return false
		if FileAccess.file_exists(dest):
			DirAccess.remove_absolute(dest)
		return DirAccess.rename_absolute(part, dest) == OK
	last_error = "Demasiadas redirecciones"
	return false


## Descomprime un .zip en una carpeta (sin compresión o deflate).
static func unzip(zip_path: String, dest_dir: String) -> bool:
	var z := ZIPReader.new()
	if z.open(zip_path) != OK:
		return false
	for f in z.get_files():
		if f.ends_with("/"):
			continue
		var out := dest_dir.path_join(f)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var w := FileAccess.open(out, FileAccess.WRITE)
		if w == null:
			z.close()
			return false
		w.store_buffer(z.read_file(f))
		w.close()
	z.close()
	return true
