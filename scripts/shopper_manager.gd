class_name ShopperManager
extends Node3D
## Spawns shoppers, decides where they go, and runs checkout lines in your own shops.

const MAX_SHOPPERS := 160

var world: WorldView
var shoppers: Array = []
var queues := {}        # unit id -> Array of Shopper waiting to pay
var serve_timers := {}  # unit id -> seconds until the cashier finishes the next customer
var _spawn_acc := 0.0


func _ready() -> void:
	Game.day_ended.connect(func(_r): clear_all())
	Game.reset.connect(clear_all)
	Game.unit_changed.connect(_on_unit_changed)


func clear_all() -> void:
	for s in shoppers:
		s.queue_free()
	shoppers.clear()
	queues.clear()
	serve_timers.clear()


func _process(delta: float) -> void:
	if not Game.running or Game.is_over or Game.speed == 0:
		return
	var d := delta * Game.speed
	if Game.is_open() and Game.minute < Data.CLOSE_MINUTE - 45:
		var hour := Game.minute / 60.0
		var curve := 0.6 + 0.8 * exp(-pow(hour - 13.0, 2) / 4.0) + 0.6 * exp(-pow(hour - 18.0, 2) / 3.0)
		var per_minute := Game.expected_visitors() / float(Data.CLOSE_MINUTE - Data.OPEN_MINUTE)
		_spawn_acc += delta * 6.0 * Game.speed * per_minute * curve
		while _spawn_acc >= 1.0:
			_spawn_acc -= 1.0
			if shoppers.size() < MAX_SHOPPERS:
				_spawn()
	for s in shoppers.duplicate():
		s.tick(d)
	_run_cashiers(d)


# --- Spawning --------------------------------------------------------------

func _spawn() -> void:
	var s := Shopper.new()
	s.manager = self
	add_child(s)
	var ent := Game.entrance_tile()
	s.position = WorldView.tile_center(ent) + Vector3(randf_range(-0.6, 0.6), 0.12, 4.0)
	s.budget = randf_range(15, 120) * (1.0 + Game.rating * 0.15)
	s.patience = randf_range(18, 35)
	# Most shoppers come for shops the mall already has; some want something it doesn't.
	var all_types := Data.SHOP_TYPES.keys()
	var have := []
	for u in _open_units():
		have.append(u["tenant"]["type"] if u["state"] == "tenant" else u["shop"]["type"])
	var n := randi_range(1, 3)
	for i in n:
		var t: String = all_types.pick_random()
		if have.size() > 0 and randf() < 0.7:
			t = have.pick_random()
		elif randf() < 0.3:
			t = Game.trend_type
		if not s.wants.has(t):
			s.wants.append(t)
	shoppers.append(s)
	Game.shopper_arrived()
	s.state = "arriving"
	s.walk_to([WorldView.tile_center(ent) + Vector3(0, 0.12, 0)])


func _leave(s: Shopper) -> void:
	s.state = "leaving"
	var ent := Game.entrance_tile()
	var here := _current_tile(s)
	var pts := _tile_path(here, ent)
	pts.append(WorldView.tile_center(ent) + Vector3(randf_range(-0.6, 0.6), 0.12, 5.0))
	s.walk_to(pts)


func _despawn(s: Shopper) -> void:
	var final_sat := s.sat - Game.dirt / 100.0 * 0.35
	if Game.dirt > 50 and s.complaint == "":
		s.complaint = "The mall is dirty"
	Game.shopper_left(final_sat, s.complaint)
	shoppers.erase(s)
	s.queue_free()


## The walkable tile the shopper is on, or the closest one.
func _current_tile(s: Shopper) -> Vector2i:
	var t := WorldView.world_to_tile(s.position)
	if Game.walkable(t):
		return t
	var best := t
	var best_d := 999.0
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var n := t + Vector2i(dx, dy)
			if Game.walkable(n):
				var d := WorldView.tile_center(n).distance_to(s.position)
				if d < best_d:
					best_d = d
					best = n
	return best


func _tile_path(from: Vector2i, to: Vector2i) -> Array:
	var ids := Game.find_path(from, to)
	var pts := []
	for i in ids.size():
		if i == 0:
			continue
		pts.append(WorldView.tile_center(ids[i]) + Vector3(randf_range(-0.45, 0.45), 0.12, randf_range(-0.45, 0.45)))
	return pts


# --- Decisions -------------------------------------------------------------

func _pick_next(s: Shopper) -> void:
	s.target_id = -1
	if not Game.is_open() or Game.minute > Data.CLOSE_MINUTE - 40 or s.budget < 3.0:
		_leave(s)
		return
	while s.wants.size() > 0:
		var want: String = s.wants.pop_front()
		var options := []
		for u in Game.units:
			if u["state"] == "vacant" or not Game.door_reachable(u):
				continue
			var t: String = u["tenant"]["type"] if u["state"] == "tenant" else u["shop"]["type"]
			if t == want:
				options.append(u)
		if options.is_empty():
			s.sat -= 0.07
			if s.complaint == "":
				s.complaint = "No %s shop" % Data.SHOP_TYPES[want]["name"]
			s.say("No %s? :(" % Data.SHOP_TYPES[want]["name"].to_lower())
			# sometimes they browse somewhere else instead
			if randf() < 0.35:
				var any := _open_units()
				if any.size() > 0:
					_go_to_unit(s, any.pick_random())
					return
			continue
		_go_to_unit(s, options.pick_random())
		return
	_leave(s)


func _open_units() -> Array:
	var out := []
	for u in Game.units:
		if u["state"] != "vacant" and Game.door_reachable(u):
			out.append(u)
	return out


func _go_to_unit(s: Shopper, u: Dictionary) -> void:
	s.target_id = u["id"]
	s.state = "to_shop"
	var here := _current_tile(s)
	var door := Game.door_tile(u["pos"], u["rot"])
	var pts := _tile_path(here, door)
	if pts.is_empty() and here != door:
		_pick_next(s)
		return
	pts.append(WorldView.tile_center(door) + Vector3(0, 0.12, 0))
	s.walk_to(pts)


## Called when a shopper reaches the end of its path.
func on_arrived(s: Shopper) -> void:
	var u = Game.unit_by_id(s.target_id) if s.target_id >= 0 else null
	var view: UnitView = world.view_for(s.target_id) if s.target_id >= 0 else null
	match s.state:
		"arriving":
			_pick_next(s)
		"leaving":
			_despawn(s)
		"to_shop":
			if u == null or view == null or u["state"] == "vacant":
				_pick_next(s)
				return
			s.sat += minf(0.06, Game.appeal_near(Game.door_tile(u["pos"], u["rot"])) * 0.012)
			s.state = "entering"
			s.walk_to([view.door_inside_global() + Vector3(0, 0.12, 0)])
		"entering":
			if u == null or view == null:
				_exit_shop(s)
				return
			if u["state"] == "tenant":
				s.state = "browsing"
				s.wait_t = randf_range(3.0, 7.0)
				s.walk_to([view.random_inside_global() + Vector3(0, 0.12, 0)])
			elif u["state"] == "owned":
				s.shelf_index = randi() % 4
				s.state = "to_shelf"
				s.walk_to([view.shelf_access_global(s.shelf_index) + Vector3(0, 0.12, 0)])
			else:
				_exit_shop(s)
		"browsing":
			pass  # handled in on_idle
		"to_shelf":
			s.state = "picking"
			s.wait_t = randf_range(1.5, 3.0)
		"to_queue":
			s.state = "queue"
		"exiting":
			s.state = "exited"
			_pick_next(s)


## Called every tick while a shopper is standing still.
func on_idle(s: Shopper, delta: float) -> void:
	var u = Game.unit_by_id(s.target_id) if s.target_id >= 0 else null
	match s.state:
		"browsing":
			s.wait_t -= delta
			if s.wait_t <= 0.0:
				if u != null and u["state"] == "tenant":
					_tenant_buy(s, u)
				_exit_shop(s)
		"picking":
			s.wait_t -= delta
			if s.wait_t <= 0.0:
				if u == null or u["state"] != "owned":
					_exit_shop(s)
				else:
					_own_pick(s, u)
		"queue":
			s.wait_t += delta
			if s.wait_t > s.patience:
				_leave_queue(s, u)
		"to_queue":
			pass


func _tenant_buy(s: Shopper, u: Dictionary) -> void:
	var t: Dictionary = u["tenant"]
	t["visits_today"] = int(t["visits_today"]) + 1
	var chance: float = 0.6 * (0.8 + t["happiness"] / 250.0)
	if t["type"] == Game.trend_type:
		chance *= 1.3
	if randf() < chance:
		var spend: float = Data.SHOP_TYPES[t["type"]]["spend"] * randf_range(0.5, 1.5)
		spend = minf(spend, s.budget)
		s.budget -= spend
		Game.tenant_sale(u, spend)
		s.sat += 0.12
		if randf() < 0.3:
			s.say("Nice!")
	else:
		s.sat += 0.02


func _own_pick(s: Shopper, u: Dictionary) -> void:
	var sh: Dictionary = u["shop"]["shelves"][s.shelf_index]
	var p: int = sh["p"]
	var price := Game.product_price(u, p)
	var base: float = Game.product(u, p)[2]
	if int(sh["stock"]) <= 0:
		s.sat -= 0.15
		s.complaint = "Your shop was out of stock"
		s.say("Out of stock!")
		u["shop"]["lost_today"] = int(u["shop"]["lost_today"]) + 1
		_exit_shop(s)
		return
	var chance := clampf(0.92 - (price / base - 1.0) * 1.1, 0.03, 0.97)
	if u["shop"]["type"] == Game.trend_type:
		chance = minf(0.98, chance * 1.25)
	if price > s.budget or randf() > chance:
		s.sat -= 0.04
		if price / base > 1.25:
			s.complaint = "Your prices are too high"
			s.say("Too pricey!")
		_exit_shop(s)
		return
	Game.take_item(u, s.shelf_index)
	Game.changed.emit()
	s.carrying = s.shelf_index
	_join_queue(s, u)


func _join_queue(s: Shopper, u: Dictionary) -> void:
	var q: Array = queues.get(u["id"], [])
	q.append(s)
	queues[u["id"]] = q
	s.wait_t = 0.0
	_update_queue_positions(u["id"])


func _update_queue_positions(unit_id: int) -> void:
	var view: UnitView = world.view_for(unit_id)
	var q: Array = queues.get(unit_id, [])
	if view == null:
		return
	for k in q.size():
		var s: Shopper = q[k]
		s.state = "to_queue"
		s.walk_to([view.queue_global(k) + Vector3(0, 0.12, 0)])


func _leave_queue(s: Shopper, u) -> void:
	var q: Array = queues.get(s.target_id, [])
	q.erase(s)
	if u != null and s.carrying >= 0:
		Game.return_item(u, s.carrying)
		Game.changed.emit()
	s.carrying = -1
	s.sat -= 0.25
	s.complaint = "The checkout line was too long"
	s.say("Too slow!")
	_update_queue_positions(s.target_id)
	_exit_shop(s)


func _exit_shop(s: Shopper) -> void:
	var view: UnitView = world.view_for(s.target_id) if s.target_id >= 0 else null
	var u = Game.unit_by_id(s.target_id) if s.target_id >= 0 else null
	s.state = "exiting"
	if view == null or u == null:
		_pick_next(s)
		return
	var door := Game.door_tile(u["pos"], u["rot"])
	s.walk_to([view.door_inside_global() + Vector3(0, 0.12, 0), WorldView.tile_center(door) + Vector3(0, 0.12, 0)])


# --- Checkout --------------------------------------------------------------

func _run_cashiers(delta: float) -> void:
	for id in queues.keys():
		var q: Array = queues[id]
		if q.is_empty():
			continue
		var u = Game.unit_by_id(id)
		if u == null or u["state"] != "owned":
			continue
		if not u["shop"]["cashier"]:
			continue
		var front: Shopper = q[0]
		if front.state != "queue":
			continue
		serve_timers[id] = serve_timers.get(id, 3.0) - delta
		if serve_timers[id] <= 0.0:
			serve_timers[id] = 3.0
			serve_front(id)


## Ring up the first customer in line. Returns true if someone was served.
func serve_front(unit_id: int) -> bool:
	var q: Array = queues.get(unit_id, [])
	if q.is_empty():
		return false
	var u = Game.unit_by_id(unit_id)
	var s: Shopper = q[0]
	if u == null or u["state"] != "owned":
		return false
	q.remove_at(0)
	var price := 0.0
	if s.carrying >= 0:
		price = Game.product_price(u, int(u["shop"]["shelves"][s.carrying]["p"]))
	Game.own_sale(u, price)
	s.budget -= price
	s.carrying = -1
	s.sat += 0.18
	s.say("+" + Data.money_str(price))
	Game.changed.emit()
	_update_queue_positions(unit_id)
	_exit_shop(s)
	return true


func queue_length(unit_id: int) -> int:
	return queues.get(unit_id, []).size()


func _on_unit_changed(id: int) -> void:
	# a unit was rebuilt or removed: anyone inside walks out
	queues.erase(id)
	for s in shoppers:
		if s.target_id != id:
			continue
		s.carrying = -1
		if s.state == "to_shop":
			_pick_next(s)
		elif s.state in ["entering", "browsing", "to_shelf", "picking", "to_queue", "queue"]:
			_exit_shop(s)
