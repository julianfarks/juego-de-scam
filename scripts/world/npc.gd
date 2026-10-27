class_name NPC
extends Node3D
## Personaje de la oficina (compañeros y jefe): sigue rutas simples por los pasillos,
## se sienta a teclear, mira al jugador y muestra bocadillos de texto.

signal arrived

var model: CharacterModel
var bubble: Label3D
var path: Array = []
var speed := 1.6
var display_name := ""
var lines: Array = []
var seat_pos := Vector3.ZERO
var seat_rot := 0.0
var seated := false
var player: Node3D
var _bubble_t := 0.0
var _talk_t := 0.0
var _idle_line_t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(look: Dictionary, p_name: String, p_lines: Array, seed_v := 0) -> void:
	display_name = p_name
	lines = p_lines
	_rng.seed = seed_v
	model = CharacterModel.new()
	add_child(model)
	model.build(look, seed_v)
	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.font_size = 40
	bubble.pixel_size = 0.004
	bubble.outline_size = 12
	bubble.modulate = Color("ffffff")
	bubble.outline_modulate = Color("1b1b22")
	bubble.position = Vector3(0, 2.25 * model.height_scale, 0)
	bubble.width = 520
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.no_depth_test = true
	bubble.visible = false
	add_child(bubble)
	_idle_line_t = _rng.randf_range(15.0, 45.0)


func sit_at(pos: Vector3, rot: float) -> void:
	seat_pos = pos
	seat_rot = rot
	global_position = pos
	model.rotation.y = rot
	seated = true
	model.state = "sit"


func go(points: Array) -> void:
	seated = false
	path = points.duplicate()
	model.state = "walk"


func say(text: String, duration := 4.0) -> void:
	bubble.text = text
	bubble.visible = true
	_bubble_t = duration
	model.play_gesture("wave" if _rng.randf() < 0.2 else "")


## Mueve la boca y gesticula sin mostrar bocadillo (p. ej. cuando habla por voz).
func talk_for(seconds: float) -> void:
	_talk_t = seconds


func _process(delta: float) -> void:
	if _talk_t > 0.0:
		_talk_t -= delta
		model.talk_amount = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 70.0) if _talk_t > 0.0 else 0.0
	if _bubble_t > 0.0:
		_bubble_t -= delta
		model.talk_amount = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 70.0) if _bubble_t > 0.5 else 0.0
		if _bubble_t <= 0.0:
			bubble.visible = false
			model.talk_amount = 0.0
	if not path.is_empty():
		var target: Vector3 = path[0]
		var to := target - global_position
		to.y = 0
		var dist := to.length()
		if dist < 0.08:
			path.pop_front()
			if path.is_empty():
				model.state = "idle"
				arrived.emit()
		else:
			var step := minf(dist, speed * delta)
			global_position += to.normalized() * step
			model.rotation.y = lerp_angle(model.rotation.y, atan2(to.x, to.z), clampf(delta * 10.0, 0, 1))
			model.walk_speed = speed
	elif not seated and player and is_instance_valid(player):
		var d := player.global_position - global_position
		if d.length() < 3.0:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(d.x, d.z), clampf(delta * 4.0, 0, 1))
	# Comentarios espontáneos de oficina
	if not lines.is_empty() and seated:
		_idle_line_t -= delta
		if _idle_line_t <= 0.0:
			_idle_line_t = _rng.randf_range(25.0, 60.0)
			if player and global_position.distance_to(player.global_position) < 7.0:
				say(lines[_rng.randi() % lines.size()], 3.5)
