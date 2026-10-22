class_name Shopper
extends Node3D
## One shopper walking around the mall. Driven by ShopperManager.

const WALK_SPEED := 1.7

var manager  # ShopperManager
var wants: Array = []
var budget := 50.0
var sat := 0.6
var complaint := ""
var patience := 25.0
var state := "to_shop"
var target_id := -1
var shelf_index := -1
var carrying := -1
var wait_t := 0.0
var path: Array = []           # world-space points to walk through
var _model: Node3D
var _bob := 0.0
var _bubble: Label3D
var _bubble_t := 0.0

const SHIRTS := [Color(0.85, 0.25, 0.3), Color(0.25, 0.5, 0.85), Color(0.3, 0.7, 0.4), Color(0.95, 0.75, 0.2),
	Color(0.6, 0.35, 0.75), Color(0.95, 0.5, 0.2), Color(0.9, 0.9, 0.92), Color(0.2, 0.2, 0.25), Color(0.4, 0.8, 0.8)]
const PANTS := [Color(0.2, 0.25, 0.4), Color(0.15, 0.15, 0.15), Color(0.45, 0.35, 0.25), Color(0.5, 0.5, 0.55)]
const SKINS := [Color(0.98, 0.84, 0.7), Color(0.85, 0.65, 0.5), Color(0.6, 0.42, 0.3), Color(0.4, 0.28, 0.2), Color(0.95, 0.76, 0.6)]
const HAIRS := [Color(0.1, 0.07, 0.05), Color(0.35, 0.2, 0.1), Color(0.85, 0.7, 0.35), Color(0.6, 0.25, 0.1), Color(0.5, 0.5, 0.5)]


func _ready() -> void:
	_model = Art.make_person(SHIRTS.pick_random(), PANTS.pick_random(), SKINS.pick_random(), HAIRS.pick_random())
	var s := randf_range(0.85, 1.08)
	_model.scale = Vector3(s, s, s)
	add_child(_model)
	_bubble = Art.label(self, "", Vector3(0, 2.2, 0), 48)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.visible = false


func say(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_t = 2.5


func walk_to(points: Array) -> void:
	path = points.duplicate()


func tick(delta: float) -> void:
	# delta is already scaled by game speed
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble.visible = false
	if path.size() > 0:
		var target: Vector3 = path[0]
		var to := target - position
		to.y = 0
		var step := WALK_SPEED * delta
		if to.length() <= step:
			position = Vector3(target.x, position.y, target.z)
			path.pop_front()
			if path.is_empty():
				manager.on_arrived(self)
		else:
			var dir := to.normalized()
			position += dir * step
			var want_rot := atan2(dir.x, dir.z)
			rotation.y = lerp_angle(rotation.y, want_rot, minf(1.0, delta * 10.0))
			_bob += delta * 9.0
			_model.position.y = absf(sin(_bob)) * 0.06
	else:
		_model.position.y = 0.0
		manager.on_idle(self, delta)
