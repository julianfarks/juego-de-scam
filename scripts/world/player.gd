class_name Player
extends CharacterBody3D
## Jugador en tercera persona: joystick virtual (o WASD), cámara orbital por arrastre,
## correr, detección del objeto interactivo más cercano.

signal focus_changed(item: Dictionary)

const WALK_SPEED := 2.6
const RUN_SPEED := 4.6
const GRAVITY := 18.0

var model: CharacterModel
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var move_input := Vector2.ZERO
var look_delta := Vector2.ZERO
var running := false
var yaw := PI
var pitch := -0.38
var frozen := false
var interactables: Array = []
var focus: Dictionary = {}
var speed_mult := 1.0
var _step_t := 0.0


func setup(look: Dictionary) -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	add_child(cs)
	model = CharacterModel.new()
	add_child(model)
	model.build(look, 7)
	cam_pivot = Node3D.new()
	cam_pivot.top_level = true
	add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 4.0
	spring.margin = 0.2
	var sph := SphereShape3D.new()
	sph.radius = 0.25
	spring.shape = sph
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 80.0
	spring.add_child(camera)
	spring.add_excluded_object(get_rid())
	camera.current = true


func rebuild_look(look: Dictionary) -> void:
	model.build(look, 7)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		look_delta += event.relative


func _physics_process(delta: float) -> void:
	var input := move_input
	if input.length() < 0.05:
		input = Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
		if Input.is_key_pressed(KEY_A):
			input.x -= 1
		if Input.is_key_pressed(KEY_D):
			input.x += 1
		if Input.is_key_pressed(KEY_W):
			input.y -= 1
		if Input.is_key_pressed(KEY_S):
			input.y += 1
		input = input.limit_length(1.0)
	if frozen:
		input = Vector2.ZERO
	# Cámara
	var sens := float(Settings.get_value("cam_sensitivity"))
	yaw -= look_delta.x * 0.005 * sens
	pitch = clampf(pitch - look_delta.y * 0.004 * sens, -1.1, -0.08)
	look_delta = Vector2.ZERO
	# Movimiento relativo a la cámara
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, yaw)
	var run := running or Input.is_key_pressed(KEY_SHIFT)
	var spd := (RUN_SPEED if run else WALK_SPEED) * speed_mult
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.2:
		var target := atan2(velocity.x, velocity.z)
		model.rotation.y = lerp_angle(model.rotation.y, target, clampf(delta * 12.0, 0, 1))
		model.state = "walk"
		model.walk_speed = flat.length()
		_step_t -= delta * flat.length()
		if _step_t <= 0.0:
			_step_t = 1.2
			Audio.play("step", -16.0, 0.15)
	elif model.state == "walk":
		model.state = "idle"
	cam_pivot.global_position = global_position + Vector3(0, 1.45, 0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	_update_focus()


func _update_focus() -> void:
	var best: Dictionary = {}
	var best_d := 999.0
	for it in interactables:
		var n: Node3D = it["node"]
		if not is_instance_valid(n) or not n.is_visible_in_tree():
			continue
		if it.get("disabled", false):
			continue
		var p := n.global_position
		var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
		if d < float(it["radius"]) and d < best_d:
			best_d = d
			best = it
	if best.get("node") != focus.get("node") or best.get("label") != focus.get("label"):
		focus = best
		focus_changed.emit(focus)


func face_towards(point: Vector3) -> void:
	var d := point - global_position
	model.rotation.y = atan2(d.x, d.z)
