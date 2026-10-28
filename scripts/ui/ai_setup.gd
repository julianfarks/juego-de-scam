class_name AISetup
extends Control
## Pantalla del primer inicio: descarga (una sola vez) los modelos de IA que hacen
## pensar, escuchar y hablar a los clientes. Sin cuentas, claves ni configuración.

signal finished

var info: Label
var bar: ProgressBar
var detail: Label
var go_btn: Button
var later_btn: Button
var _running := false
var _done := false
var _load_requested := false


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var md := UIKit.modal(self, 900)
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label("Despertando a los clientes", 34, UIKit.C_ACCENT))
	var gb := Brain.missing_bytes() / 1073741824.0
	info = UIKit.label("En TeleTimo los clientes piensan, te escuchan y te hablan con una IA que funciona dentro de tu móvil, sin Internet y sin cuentas.\n\nPara eso, la primera vez hay que descargar sus modelos: %.1f GB (cerebro, oído y voces). Te recomendamos usar Wi‑Fi. Después ya no hace falta conexión." % gb + ("\n\nTu móvil tiene menos de 5 GB de RAM: se usará el cerebro ligero, que conversa con mucha menos coherencia." if Brain.llm_pack == "llm_ligero" else ""), 22)
	box.add_child(info)
	bar = UIKit.bar(0, 100, UIKit.C_GOOD, 26)
	bar.visible = false
	box.add_child(bar)
	detail = UIKit.label("", 20, UIKit.C_MUTED)
	box.add_child(detail)
	var h := UIKit.hbox(10)
	box.add_child(h)
	go_btn = UIKit.button("Descargar ahora", _start, UIKit.C_GOOD, 72, 26)
	go_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(go_btn)
	later_btn = UIKit.button("Más tarde (jugar con diálogo básico)", _later, UIKit.C_PANEL2, 72, 20)
	h.add_child(later_btn)
	box.add_child(UIKit.label("Mientras no estén los modelos puedes jugar igual, pero los clientes usan un diálogo básico por reglas (no es IA) y solo podrás escribir.", 18, UIKit.C_MUTED))
	Brain.download_progress.connect(_on_progress)


func _on_progress(done: int, total: int, label: String) -> void:
	bar.value = 100.0 * done / maxf(1.0, total)
	detail.text = "%s — %.0f de %.0f MB" % [label, done / 1048576.0, total / 1048576.0]


func _start() -> void:
	if _done:
		_later()
		return
	if _running:
		return
	_running = true
	go_btn.disabled = true
	later_btn.text = "Seguir en segundo plano"
	bar.visible = true
	detail.text = "Conectando…"
	if not Brain.downloading:
		Brain.download_all()


func _process(_delta: float) -> void:
	if Brain.downloading and not _running:
		_running = true
		go_btn.disabled = true
		bar.visible = true
		later_btn.text = "Seguir en segundo plano"
	if not _running or _done:
		return
	if Brain.downloading:
		return
	if Brain.missing_packs().is_empty():
		if Brain.llm_state == "ready":
			_done = true
			Settings.set_value("ai_setup_seen", true)
			detail.text = Brain.status_text()
			go_btn.text = "¡Listo! A trabajar"
			go_btn.disabled = false
			bar.value = 100
		else:
			if Brain.llm_state == "error" and _load_requested:
				detail.text = "No se pudo cargar la IA: %s" % Brain.last_error
				_done = true
				go_btn.text = "Continuar sin IA"
				go_btn.disabled = false
			else:
				detail.text = "Cargando la IA en memoria…"
				if Brain.llm_state in ["missing", "error"] and not _load_requested:
					_load_requested = true
					Brain.load_all()
	else:
		_running = false
		go_btn.disabled = false
		go_btn.text = "Reintentar (continúa donde se quedó)"
		detail.text = "No se pudo completar: %s" % Brain.last_error


func _later() -> void:
	Settings.set_value("ai_setup_seen", true)
	finished.emit()
	queue_free()


func _exit_tree() -> void:
	if Brain.download_progress.is_connected(_on_progress):
		Brain.download_progress.disconnect(_on_progress)
