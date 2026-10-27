class_name ClientStage
extends SubViewport
## «Videollamada» del cliente: su casa en miniatura y el personaje 3D al teléfono,
## renderizado en un SubViewport con mundo propio (barato: resolución reducida).

var model: CharacterModel
var world_root: Node3D
var camera: Camera3D
var client_id := ""
var speaking := false
var _t := 0.0


func _init() -> void:
	own_world_3d = true
	transparent_bg = false
	size = Vector2i(512, 420)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_DISABLED


func show_client(id: String) -> void:
	client_id = id
	if world_root:
		world_root.queue_free()
	world_root = Node3D.new()
	add_child(world_root)
	var c := ClientDB.get_c(id)
	var home: Dictionary = c["home"]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(home["wall"]).darkened(0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff3e0")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world_root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.0
	world_root.add_child(key)
	var b := OfficeBuilder.new()
	b.root = world_root
	var wall := CharacterModel.mat(home["wall"])
	b.box_at(world_root, Vector3(6, 4, 0.2), Vector3(0, 1.5, -1.2), wall)
	b.box_at(world_root, Vector3(6, 0.1, 4), Vector3(0, 0, 0), CharacterModel.mat(Color(home["wall"]).darkened(0.45).to_html(false)))
	# Ventana con cielo
	b.box_at(world_root, Vector3(1.2, 0.9, 0.05), Vector3(-1.3, 1.9, -1.08), CharacterModel.mat("ffffff"))
	b.box_at(world_root, Vector3(1.05, 0.75, 0.02), Vector3(-1.3, 1.9, -1.05), OfficeBuilder.emissive("8ecae6", 0.9))
	b.box_at(world_root, Vector3(1.05, 0.04, 0.03), Vector3(-1.3, 1.9, -1.04), CharacterModel.mat("ffffff"))
	_prop(b, str(home["prop"]))
	model = CharacterModel.new()
	world_root.add_child(model)
	model.build(c["look"], absi(hash(id)))
	model.state = "phone"
	model.set_phone(true)
	model.position = Vector3(0.15, 0, 0)
	model.rotation.y = -0.15
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.position = Vector3(0.05, 1.55 * model.height_scale, 2.3)
	camera.rotation_degrees = Vector3(-4, 0, 0)
	world_root.add_child(camera)
	camera.current = true


func _prop(b: OfficeBuilder, kind: String) -> void:
	match kind:
		"bookshelf":
			b.box_at(world_root, Vector3(1.0, 2.0, 0.35), Vector3(1.4, 1.0, -0.95), CharacterModel.mat("6b4226"))
			var cols := ["e63946", "457b9d", "f4a261", "2a9d8f", "8338ec"]
			for row in 3:
				for i in 6:
					b.box_at(world_root, Vector3(0.1, 0.28, 0.22), Vector3(1.05 + i * 0.13, 0.5 + row * 0.6, -0.8), CharacterModel.mat(cols[(i + row) % 5]))
		"tv":
			b.box_at(world_root, Vector3(0.9, 0.55, 0.06), Vector3(1.4, 1.3, -1.05), CharacterModel.mat("15151a"))
			b.box_at(world_root, Vector3(0.82, 0.47, 0.02), Vector3(1.4, 1.3, -1.01), OfficeBuilder.emissive("4cc9f0", 1.0))
		"plant":
			b.mesh_at(world_root, CharacterModel.cylinder(0.18, 0.14, 0.35), Vector3(1.3, 0.18, -0.6), CharacterModel.mat("b5651d"))
			for k in 3:
				b.mesh_at(world_root, CharacterModel.sphere(0.25), Vector3(1.3 + sin(k * 2.0) * 0.1, 0.6 + k * 0.2, -0.6), CharacterModel.mat("2e7d32"))
		"lamp":
			b.mesh_at(world_root, CharacterModel.cylinder(0.02, 0.02, 1.4), Vector3(1.3, 0.7, -0.7), CharacterModel.mat("333333"))
			b.mesh_at(world_root, CharacterModel.cylinder(0.12, 0.28, 0.3), Vector3(1.3, 1.5, -0.7), OfficeBuilder.emissive("ffe8a3", 1.4))
		"aquarium":
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.4, 0.7, 1.0, 0.5)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			b.box_at(world_root, Vector3(0.8, 0.5, 0.4), Vector3(1.4, 1.05, -0.85), glass)
			b.box_at(world_root, Vector3(0.9, 0.8, 0.45), Vector3(1.4, 0.4, -0.85), CharacterModel.mat("3d405b"))
			b.mesh_at(world_root, CharacterModel.sphere(0.06), Vector3(1.35, 1.05, -0.8), CharacterModel.mat("ff9f1c"), Vector3(1.6, 1, 0.6))
		"guitar":
			b.mesh_at(world_root, CharacterModel.sphere(0.22), Vector3(1.35, 0.55, -0.9), CharacterModel.mat("c1793b"), Vector3(1, 1.2, 0.35))
			b.box_at(world_root, Vector3(0.06, 0.7, 0.04), Vector3(1.35, 1.05, -0.9), CharacterModel.mat("4a2e1a"))
		"trophies":
			b.box_at(world_root, Vector3(1.2, 0.08, 0.3), Vector3(1.3, 1.4, -1.0), CharacterModel.mat("8b5e3c"))
			for i in 3:
				b.mesh_at(world_root, CharacterModel.cylinder(0.08, 0.04, 0.25), Vector3(0.95 + i * 0.35, 1.57, -1.0), CharacterModel.mat("e0b030", 0.3, 0.8))


func set_emotion(e: String) -> void:
	if model:
		model.set_emotion(e)


func gesture(g: String) -> void:
	if model:
		model.play_gesture(g)


func _process(delta: float) -> void:
	_t += delta
	if model == null:
		return
	model.talk_amount = Voice.mouth_open(_t) if speaking else lerpf(model.talk_amount, 0.0, delta * 10.0)
