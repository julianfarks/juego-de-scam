class_name AILog
extends RefCounted
## Registro técnico de la IA (carga de modelos, tiempos, errores) para poder
## diagnosticar en el móvil del jugador. Se guarda en user://ia/diagnostico.log,
## se puede ver y copiar desde Ajustes → IA y voz → Diagnóstico.
## No guarda lo que dice el jugador: solo tiempos, tamaños y errores.

const PATH := "user://ia/diagnostico.log"
const MAX_BYTES := 60000

static var _lines: Array = []


static func add(stage: String, msg: String) -> void:
	var dt := Time.get_datetime_string_from_system(false, true)
	var line := "%s [%s] %s" % [dt, stage, msg]
	print("IA ", line)
	_lines.append(line)
	if _lines.size() > 400:
		_lines = _lines.slice(_lines.size() - 400)
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var f := FileAccess.open(PATH, FileAccess.READ_WRITE) if FileAccess.file_exists(PATH) else FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	if f.get_length() > MAX_BYTES:
		# Conserva la mitad más reciente
		f.seek(f.get_length() - MAX_BYTES / 2)
		var tail := f.get_buffer(MAX_BYTES / 2).get_string_from_utf8()
		f.close()
		f = FileAccess.open(PATH, FileAccess.WRITE)
		if f == null:
			return
		f.store_string(tail.substr(tail.find("\n") + 1))
	f.seek_end()
	f.store_line(line)
	f.close()


static func text() -> String:
	if FileAccess.file_exists(PATH):
		return FileAccess.get_file_as_string(PATH)
	return "\n".join(PackedStringArray(_lines))


static func clear() -> void:
	_lines.clear()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
