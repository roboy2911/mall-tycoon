class_name CameraRig
extends Node3D
## Tilted top-down camera. WASD/arrows to pan, Q/E or right-drag to rotate, mouse wheel to zoom.

var camera: Camera3D
var yaw := 0.0
var pitch := deg_to_rad(-55.0)
var distance := 38.0
var _target_distance := 38.0
var _dragging := false
var enabled := true


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 400.0
	add_child(camera)
	position = Vector3(Data.GRID_W * Data.TILE / 2, 0, Data.GRID_H * Data.TILE * 0.75)
	_apply()


func _apply() -> void:
	rotation = Vector3(0, yaw, 0)
	var offset := Vector3(0, 0, distance).rotated(Vector3.RIGHT, pitch)
	camera.position = offset
	camera.rotation = Vector3(pitch, 0, 0)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_target_distance = maxf(10.0, _target_distance * 0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_target_distance = minf(90.0, _target_distance * 1.12)
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch - event.relative.y * 0.004, deg_to_rad(-85), deg_to_rad(-25))


func _process(delta: float) -> void:
	if not enabled:
		return
	var move := Vector3.ZERO
	if not _typing():
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.z -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.z += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1
		if Input.is_key_pressed(KEY_Q):
			yaw += delta * 1.6
		if Input.is_key_pressed(KEY_E):
			yaw -= delta * 1.6
	if move != Vector3.ZERO:
		var pan_speed := distance * 0.9
		position += move.normalized().rotated(Vector3.UP, yaw) * pan_speed * delta
		position.x = clampf(position.x, -10, Data.GRID_W * Data.TILE + 10)
		position.z = clampf(position.z, -10, Data.GRID_H * Data.TILE + 25)
	distance = lerpf(distance, _target_distance, minf(1.0, delta * 8.0))
	_apply()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## Point on the ground (y = 0) under the mouse, or null.
func mouse_ground_point():
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return null
	var t := -from.y / dir.y
	if t < 0:
		return null
	return from + dir * t


func focus_on(p: Vector3) -> void:
	position = Vector3(p.x, 0, p.z)
