class_name FPPlayer
extends CharacterBody3D
## First-person player used inside your own shops. WASD to walk, mouse to look, E / left click to interact.

signal hover_changed(text: String)

const SPEED := 3.2
const SENS := 0.0025

var camera: Camera3D
var ray: RayCast3D
var _pitch := 0.0
var _hover := ""
var shop_view: Node3D


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	camera.fov = 75.0
	camera.near = 0.05
	add_child(camera)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.2)
	ray.collide_with_bodies = true
	camera.add_child(ray)
	# simple hands holding a stock box, so it feels like you're working
	var hands := Node3D.new()
	hands.position = Vector3(0.35, -0.35, -0.6)
	camera.add_child(hands)
	Art.box(hands, Vector3(0.09, 0.09, 0.35), Vector3(-0.12, 0, 0), Color(0.95, 0.8, 0.65))
	Art.box(hands, Vector3(0.12, 0.12, 0.3), Vector3(-0.12, 0, 0.14), Color(0.2, 0.4, 0.8))


func activate(at: Vector3, facing_yaw: float) -> void:
	global_position = at
	rotation = Vector3(0, facing_yaw, 0)
	_pitch = 0.0
	camera.rotation = Vector3.ZERO
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * SENS
		_pitch = clampf(_pitch - event.relative.y * SENS, -1.3, 1.3)
		camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input.y -= 1
	if Input.is_key_pressed(KEY_S): input.y += 1
	if Input.is_key_pressed(KEY_A): input.x -= 1
	if Input.is_key_pressed(KEY_D): input.x += 1
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	velocity.y = 0
	move_and_slide()
	# stay on the shop floor and inside the shop
	global_position.y = 0.12
	if shop_view:
		var local := shop_view.to_local(global_position)
		local.x = clampf(local.x, -2.7, 2.7)
		local.z = clampf(local.z, -2.7, 2.7)
		local.y = 0.12
		global_position = shop_view.to_global(local)

	var text := ""
	if ray.is_colliding():
		var c = ray.get_collider()
		if c and c.has_meta("interact"):
			text = describe(c.get_meta("interact"))
	if text != _hover:
		_hover = text
		hover_changed.emit(text)


func looking_at():
	if ray.is_colliding():
		var c = ray.get_collider()
		if c and c.has_meta("interact"):
			return c.get_meta("interact")
	return null


func describe(info: Dictionary) -> String:
	var u = Game.unit_by_id(info["unit"])
	if u == null or u["state"] != "owned":
		return ""
	if info["kind"] == "shelf":
		var sh: Dictionary = u["shop"]["shelves"][info["index"]]
		var p: int = sh["p"]
		var name: String = Game.product(u, p)[0]
		return "%s shelf: %d/%d   (back room: %d)\n[E] Restock    [F] Switch product" % [name, sh["stock"], Game.SHELF_CAP, u["shop"]["back"][p]]
	if info["kind"] == "register":
		return "Cash register\n[E] Serve next customer"
	return ""
