extends Node
## Guardado local versionado (JSON) con escritura atómica y copia de seguridad.
## Solo progreso de juego: nunca claves, audio de voz ni datos financieros reales.

signal saved
signal loaded

const SAVE_VERSION := 2
const PATH := "user://save.json"
const BACKUP_PATH := "user://save.bak.json"
const TMP_PATH := "user://save.tmp.json"
const MAX_LIST := {"crm": 60, "transactions": 80, "emails": 40, "evaluations": 40, "callbacks": 10}

var data: Dictionary = {}
var path_override := ""  # usado por las pruebas


func _ready() -> void:
	load_game()


static func default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"created_unix": int(Time.get_unix_time_from_system()),
		"updated_unix": 0,
		"player_name": "Novato",
		"tutorial_done": false,
		"campaign": {"current_day": 1, "max_day_unlocked": 1, "completed_days": [], "day_grades": {}, "strikes": 0},
		"money": 150,
		"career_earnings": 0,
		"upgrades_owned": [],
		"cosmetics_owned": ["hair_short", "shirt_blue"],
		"equipped": {"hat": "", "glasses": "", "tie": "", "shirt": "shirt_blue", "hair": "hair_short", "deco": []},
		"stats": {
			"days_completed": 0, "calls_made": 0, "transactions": 0, "money_total": 0,
			"successes": 0, "failures": 0, "hangups": 0, "clients_served": {},
			"record_day_income": 0, "objectives_completed": 0, "contradictions_caught": 0,
			"voice_turns": 0, "text_turns": 0, "longest_call_s": 0, "best_grade": "",
		},
		"achievements": [],
		"crm": [],
		"callbacks": [],
		"transactions": [],
		"emails": [],
		"evaluations": [],
	}


func _path() -> String:
	return path_override if path_override != "" else PATH


func load_game() -> bool:
	data = default_data()
	var p := _path()
	if not FileAccess.file_exists(p):
		loaded.emit()
		return false
	var parsed: Variant = _read_json(p)
	if parsed == null and FileAccess.file_exists(BACKUP_PATH) and path_override == "":
		push_warning("Guardado dañado; usando la copia de seguridad")
		parsed = _read_json(BACKUP_PATH)
	if parsed is Dictionary:
		data = migrate(parsed)
	loaded.emit()
	return parsed is Dictionary


func _read_json(p: String) -> Variant:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(txt) != OK:
		return null
	return json.data


## Lleva cualquier versión anterior al esquema actual y repara campos inválidos.
static func migrate(raw: Dictionary) -> Dictionary:
	var d := raw.duplicate(true)
	var v := int(d.get("version", 1))
	if v < 2:
		# v1 usaba "cash" y una lista plana "upgrades"
		if d.has("cash") and not d.has("money"):
			d["money"] = d["cash"]
		if d.has("upgrades") and not d.has("upgrades_owned"):
			d["upgrades_owned"] = d["upgrades"]
		d.erase("cash")
		d.erase("upgrades")
		v = 2
	var out := default_data()
	_merge_into(out, d)
	out["version"] = SAVE_VERSION
	_validate(out)
	return out


static func _merge_into(base: Dictionary, src: Dictionary) -> void:
	for k in src.keys():
		if not base.has(k):
			continue
		if base[k] is Dictionary and src[k] is Dictionary and k != "clients_served" and k != "day_grades":
			_merge_into(base[k], src[k])
		elif typeof(base[k]) == typeof(src[k]) or (base[k] is float and src[k] is int) or (base[k] is int and src[k] is float):
			base[k] = src[k]


static func _validate(d: Dictionary) -> void:
	d["money"] = clampi(int(d["money"]), -999999, 99999999)
	d["career_earnings"] = maxi(0, int(d["career_earnings"]))
	var c: Dictionary = d["campaign"]
	c["current_day"] = clampi(int(c["current_day"]), 1, 999)
	c["max_day_unlocked"] = clampi(int(c["max_day_unlocked"]), 1, 999)
	c["strikes"] = clampi(int(c["strikes"]), 0, 3)
	for key in MAX_LIST.keys():
		var arr: Array = d[key]
		while arr.size() > MAX_LIST[key]:
			arr.pop_front()
	for key in d["stats"].keys():
		if d["stats"][key] is float:
			d["stats"][key] = int(d["stats"][key])


func save_game() -> bool:
	data["updated_unix"] = int(Time.get_unix_time_from_system())
	_validate(data)
	var txt := JSON.stringify(data, "\t")
	var p := _path()
	var tmp := TMP_PATH if path_override == "" else p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("No se pudo escribir el guardado: %s" % FileAccess.get_open_error())
		return false
	f.store_string(txt)
	f.close()
	var dir := DirAccess.open("user://")
	if path_override == "" and FileAccess.file_exists(p):
		dir.copy(p, BACKUP_PATH)
	var err := dir.rename(tmp, p)
	if err != OK:
		push_warning("No se pudo reemplazar el guardado (%d)" % err)
		return false
	saved.emit()
	return true


func has_progress() -> bool:
	return FileAccess.file_exists(_path()) and (int(data["campaign"]["max_day_unlocked"]) > 1 or int(data["stats"]["calls_made"]) > 0)


func reset_game() -> void:
	data = default_data()
	save_game()


func push_capped(list_key: String, item: Variant) -> void:
	var arr: Array = data[list_key]
	arr.append(item)
	while arr.size() > MAX_LIST.get(list_key, 100):
		arr.pop_front()


func stat_add(key: String, amount: int = 1) -> void:
	var s: Dictionary = data["stats"]
	s[key] = int(s.get(key, 0)) + amount
