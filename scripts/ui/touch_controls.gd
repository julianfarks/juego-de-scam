class_name TouchControls
extends Control
## Joystick virtual dinámico (mitad izquierda) y arrastre de cámara (mitad derecha),
## multitáctil. Los toques que empiezan sobre un botón se ignoran.

signal move(v: Vector2)
signal look(delta: Vector2)

var radius := 110.0
var base_pos := Vector2.ZERO
var knob := Vector2.ZERO
var joy_index := -1
var cam_index := -1
var cam_last := Vector2.ZERO
var exclusions: Array[Control] = []
var enabled := true
var swap := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_settings()
	Settings.changed.connect(func(k: String) -> void:
		if k in ["joystick_scale", "swap_sides"]:
			_apply_settings())


func _apply_settings() -> void:
	radius = 110.0 * float(Settings.get_value("joystick_scale"))
	swap = bool(Settings.get_value("swap_sides"))
	queue_redraw()


func default_base() -> Vector2:
	var s := get_viewport_rect().size
	var x := radius + 70.0
	return Vector2(s.x - x if swap else x, s.y - radius - 60.0)


func _is_joy_side(p: Vector2) -> bool:
	var half := get_viewport_rect().size.x * 0.45
	return (p.x > get_viewport_rect().size.x - half) if swap else (p.x < half)


func _over_exclusion(p: Vector2) -> bool:
	for c in exclusions:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().grow(6).has_point(p):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _over_exclusion(event.position):
				return
			if joy_index == -1 and _is_joy_side(event.position) and event.position.y > get_viewport_rect().size.y * 0.3:
				joy_index = event.index
				base_pos = event.position
				knob = Vector2.ZERO
				queue_redraw()
			elif cam_index == -1:
				cam_index = event.index
				cam_last = event.position
		else:
			if event.index == joy_index:
				joy_index = -1
				knob = Vector2.ZERO
				move.emit(Vector2.ZERO)
				queue_redraw()
			elif event.index == cam_index:
				cam_index = -1
	elif event is InputEventScreenDrag:
		if event.index == joy_index:
			var d: Vector2 = event.position - base_pos
			knob = d.limit_length(radius)
			move.emit(knob / radius)
			queue_redraw()
		elif event.index == cam_index:
			look.emit(event.position - cam_last)
			cam_last = event.position


func release_all() -> void:
	joy_index = -1
	cam_index = -1
	knob = Vector2.ZERO
	move.emit(Vector2.ZERO)
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var b := base_pos if joy_index != -1 else default_base()
	draw_circle(b, radius, Color(1, 1, 1, 0.10))
	draw_arc(b, radius, 0, TAU, 48, Color(1, 1, 1, 0.35), 4.0, true)
	draw_circle(b + knob, radius * 0.42, Color(1.0, 0.79, 0.24, 0.75 if joy_index != -1 else 0.4))
