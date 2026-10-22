extends Node
## Global game state and simulation (autoloaded as "Game").
## Holds all data that gets saved. The 3D world and UI read from here and react to signals.

signal changed                       # something the UI shows has changed
signal notify(text: String, kind: String)  # kind: info / good / bad
signal tiles_changed                 # floor or decor layout changed
signal unit_changed(unit_id: int)    # a unit was added, removed or changed state
signal day_started
signal day_ended(report: Dictionary)
signal game_over(reason: String)
signal level_up(level: int)
signal reset                         # a new game started or a save was loaded

const SAVE_PATH := "user://mall_save.json"

# --- Saved state -----------------------------------------------------------
var money := 0.0
var day := 1
var minute := 0.0
var grid := {}            # Vector2i -> "floor" | "entrance"
var decor := {}           # Vector2i -> decor id
var units: Array = []     # Array of unit dictionaries
var next_unit_id := 1
var applicants: Array = []
var requests: Array = []  # tenant requests waiting for a decision
var xp := 0
var level := 1
var rating := 1.0
var completed_goals: Array = []
var marketing: Array = [] # {name, mult, days}
var loan := 0.0
var debt_days := 0
var cleaners := 0
var security := 0
var dirt := 0.0           # 0..100
var trend_type := "cafe"
var rival_strength := 0.0
var best_visitors := 0
var best_own_sales := 0.0
var history: Array = []
var today := {}

# --- Runtime only ----------------------------------------------------------
var speed := 1            # 0 = paused, 1, 2, 4
var running := false      # false while menus / day report are open
var is_over := false
var astar := AStarGrid2D.new()
var _last_hour := -1
var _goal_check_timer := 0.0


func _ready() -> void:
	astar.region = Rect2i(0, 0, Data.GRID_W, Data.GRID_H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()


# ===========================================================================
# New game / save / load
# ===========================================================================

func new_game() -> void:
	reset.emit()
	money = Data.START_MONEY
	day = 1
	minute = Data.OPEN_MINUTE - 30
	grid.clear()
	decor.clear()
	units.clear()
	next_unit_id = 1
	applicants.clear()
	requests.clear()
	xp = 0
	level = 1
	rating = 1.2
	completed_goals.clear()
	marketing.clear()
	loan = 0.0
	debt_days = 0
	cleaners = 0
	security = 0
	dirt = 10.0
	trend_type = _random_type()
	rival_strength = 0.0
	best_visitors = 0
	best_own_sales = 0.0
	history.clear()
	is_over = false
	_reset_today()

	# A small, run-down strip mall: entrance at the bottom, a 2-wide hallway, four units.
	var cx := Data.GRID_W / 2
	var bottom := Data.GRID_H - 1
	grid[Vector2i(cx, bottom)] = "entrance"
	grid[Vector2i(cx + 1, bottom)] = "floor"
	for y in range(bottom - 8, bottom):
		grid[Vector2i(cx, y)] = "floor"
		grid[Vector2i(cx + 1, y)] = "floor"
	# units on the left (door facing east) and right (door facing west) of the hallway
	_add_unit(Vector2i(cx - 3, bottom - 4), 1)
	_add_unit(Vector2i(cx - 3, bottom - 7), 1)
	_add_unit(Vector2i(cx + 2, bottom - 4), 3)
	_add_unit(Vector2i(cx + 2, bottom - 7), 3)
	decor[Vector2i(cx, bottom - 8)] = "plant"
	decor[Vector2i(cx + 1, bottom - 8)] = "plant"

	# two tenants already rent here
	var a := _make_applicant("cafe")
	var b := _make_applicant("clothing")
	units[0]["state"] = "tenant"
	units[0]["tenant"] = a
	units[2]["state"] = "tenant"
	units[2]["tenant"] = b
	for i in 3:
		applicants.append(_make_applicant())

	rebuild_paths()
	running = true
	tiles_changed.emit()
	for u in units:
		unit_changed.emit(u["id"])
	day_started.emit()
	changed.emit()
	notify.emit("Welcome to your new mall! Lease empty units, open your own shop, and don't go broke.", "info")


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func save_game() -> void:
	if is_over:
		return
	var d := {
		"version": 1,
		"money": money, "day": day, "grid": _vec_dict_to_save(grid), "decor": _vec_dict_to_save(decor),
		"units": _units_to_save(), "next_unit_id": next_unit_id, "applicants": applicants, "requests": requests,
		"xp": xp, "level": level, "rating": rating, "completed_goals": completed_goals, "marketing": marketing,
		"loan": loan, "debt_days": debt_days, "cleaners": cleaners, "security": security, "dirt": dirt,
		"trend_type": trend_type, "rival_strength": rival_strength, "best_visitors": best_visitors,
		"best_own_sales": best_own_sales, "history": history,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return false
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return false
	reset.emit()
	money = d.get("money", Data.START_MONEY)
	day = int(d.get("day", 1))
	grid = _vec_dict_from_save(d.get("grid", {}))
	decor = _vec_dict_from_save(d.get("decor", {}))
	units = _units_from_save(d.get("units", []))
	next_unit_id = int(d.get("next_unit_id", units.size() + 1))
	applicants = d.get("applicants", [])
	requests = d.get("requests", [])
	xp = int(d.get("xp", 0))
	level = int(d.get("level", 1))
	rating = d.get("rating", 1.0)
	completed_goals = []
	for g in d.get("completed_goals", []):
		completed_goals.append(int(g))
	marketing = d.get("marketing", [])
	loan = d.get("loan", 0.0)
	debt_days = int(d.get("debt_days", 0))
	cleaners = int(d.get("cleaners", 0))
	security = int(d.get("security", 0))
	dirt = d.get("dirt", 0.0)
	trend_type = d.get("trend_type", "cafe")
	rival_strength = d.get("rival_strength", 0.0)
	best_visitors = int(d.get("best_visitors", 0))
	best_own_sales = d.get("best_own_sales", 0.0)
	history = d.get("history", [])
	is_over = false
	minute = Data.OPEN_MINUTE - 30
	_reset_today()
	rebuild_paths()
	running = true
	tiles_changed.emit()
	for u in units:
		unit_changed.emit(u["id"])
	day_started.emit()
	changed.emit()
	notify.emit("Welcome back! Day %d." % day, "info")
	return true


func _vec_dict_to_save(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out["%d,%d" % [k.x, k.y]] = src[k]
	return out


func _vec_dict_from_save(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		var parts: PackedStringArray = k.split(",")
		out[Vector2i(int(parts[0]), int(parts[1]))] = src[k]
	return out


func _units_to_save() -> Array:
	var out := []
	for u in units:
		var c: Dictionary = u.duplicate(true)
		c["pos"] = [u["pos"].x, u["pos"].y]
		out.append(c)
	return out


func _units_from_save(src: Array) -> Array:
	var out := []
	for u in src:
		var c: Dictionary = u
		c["pos"] = Vector2i(int(u["pos"][0]), int(u["pos"][1]))
		c["id"] = int(c["id"])
		c["rot"] = int(c["rot"])
		if c.get("shop") != null:
			var s: Dictionary = c["shop"]
			for sh in s["shelves"]:
				sh["p"] = int(sh["p"])
				sh["stock"] = int(sh["stock"])
			var back := []
			for v in s["back"]:
				back.append(int(v))
			s["back"] = back
		out.append(c)
	return out


func _reset_today() -> void:
	today = {
		"visitors": 0, "own_sales": 0.0, "own_cost": 0.0, "rent": 0.0, "tenant_sales": 0.0,
		"expenses": 0.0, "build": 0.0, "sat_sum": 0.0, "sat_count": 0, "complaints": {},
		"start_money": money,
	}
	_last_hour = -1


# ===========================================================================
# Time
# ===========================================================================

func _process(delta: float) -> void:
	if not running or is_over or speed == 0:
		return
	minute += delta * 6.0 * speed   # 1 real second = 6 game minutes at 1x
	var hour := int(minute) / 60
	if hour != _last_hour:
		_last_hour = hour
		_on_hour()
	_goal_check_timer -= delta
	if _goal_check_timer <= 0.0:
		_goal_check_timer = 1.0
		check_goals()
	if minute >= Data.CLOSE_MINUTE:
		minute = Data.CLOSE_MINUTE
		end_day()


func is_open() -> bool:
	return minute >= Data.OPEN_MINUTE and minute < Data.CLOSE_MINUTE


func season() -> String:
	return Data.SEASONS[((day - 1) / Data.DAYS_PER_SEASON) % 4]


func day_of_season() -> int:
	return (day - 1) % Data.DAYS_PER_SEASON + 1


func _on_hour() -> void:
	# deliveries, auto restock and cleaning happen every game hour
	for u in units:
		if u["state"] != "owned":
			continue
		var s: Dictionary = u["shop"]
		var still := []
		for o in s["orders"]:
			if minute >= o["at"]:
				s["back"][int(o["p"])] += int(o["qty"])
			else:
				still.append(o)
		if still.size() != s["orders"].size():
			notify.emit("A stock delivery arrived at your %s." % Data.SHOP_TYPES[s["type"]]["name"], "info")
		s["orders"] = still
		if s["stocker"]:
			for i in s["shelves"].size():
				restock_shelf(u, i)
	var clean_power := 1.5 + cleaners * 7.0  # the mall always has a little basic cleaning
	dirt = clampf(dirt - clean_power, 0.0, 100.0)
	changed.emit()


# ===========================================================================
# Grid / building
# ===========================================================================

func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < Data.GRID_W and t.y < Data.GRID_H


func unit_at(t: Vector2i) -> Variant:
	for u in units:
		var p: Vector2i = u["pos"]
		if t.x >= p.x and t.x < p.x + Data.UNIT_SIZE and t.y >= p.y and t.y < p.y + Data.UNIT_SIZE:
			return u
	return null


func unit_by_id(id: int) -> Variant:
	for u in units:
		if u["id"] == id:
			return u
	return null


func tile_empty(t: Vector2i) -> bool:
	return in_bounds(t) and not grid.has(t) and unit_at(t) == null


static func door_tile(pos: Vector2i, rot: int) -> Vector2i:
	match rot:
		0: return Vector2i(pos.x + 1, pos.y + 3)  # door faces +y (south / toward camera)
		1: return Vector2i(pos.x + 3, pos.y + 1)  # faces +x (east)
		2: return Vector2i(pos.x + 1, pos.y - 1)  # faces -y (north)
		_: return Vector2i(pos.x - 1, pos.y + 1)  # faces -x (west)


func can_afford(cost: float) -> bool:
	return money >= cost


func can_place_unit(pos: Vector2i, rot: int) -> bool:
	for x in Data.UNIT_SIZE:
		for y in Data.UNIT_SIZE:
			if not tile_empty(pos + Vector2i(x, y)):
				return false
	return in_bounds(door_tile(pos, rot))


func place_unit(pos: Vector2i, rot: int) -> bool:
	var cost: int = Data.BUILD["unit"]["cost"]
	if not can_place_unit(pos, rot):
		return false
	if not _pay(cost, "build"):
		return false
	var u := _add_unit(pos, rot)
	rebuild_paths()
	unit_changed.emit(u["id"])
	if not door_reachable(u):
		notify.emit("Tip: connect the shop's door (the arrow) to a floor tile so shoppers can get in.", "info")
	changed.emit()
	return true


func _add_unit(pos: Vector2i, rot: int) -> Dictionary:
	var u := {"id": next_unit_id, "pos": pos, "rot": rot, "state": "vacant", "tenant": null, "shop": null}
	next_unit_id += 1
	units.append(u)
	return u


func can_place_floor(t: Vector2i) -> bool:
	return tile_empty(t)


func place_floor(t: Vector2i) -> bool:
	if not can_place_floor(t):
		return false
	if not _pay(Data.BUILD["corridor"]["cost"], "build"):
		return false
	grid[t] = "floor"
	rebuild_paths()
	tiles_changed.emit()
	changed.emit()
	return true


func can_place_decor(t: Vector2i) -> bool:
	return grid.get(t, "") == "floor" and not decor.has(t)


func place_decor(t: Vector2i, kind: String) -> bool:
	if not can_place_decor(t):
		return false
	# don't let decorations cut shoppers off from a shop
	var reachable_before := []
	for u in units:
		if door_reachable(u):
			reachable_before.append(u)
	decor[t] = kind
	rebuild_paths()
	var blocks := t == entrance_tile()
	for u in reachable_before:
		if not door_reachable(u):
			blocks = true
	if blocks:
		decor.erase(t)
		rebuild_paths()
		notify.emit("You can't put that there: it would block shoppers from reaching a shop.", "bad")
		return false
	if not _pay(Data.BUILD[kind]["cost"], "build"):
		decor.erase(t)
		rebuild_paths()
		return false
	tiles_changed.emit()
	changed.emit()
	return true


## Bulldoze whatever is on the tile. Refunds half the price.
func bulldoze(t: Vector2i) -> bool:
	if decor.has(t):
		money += Data.BUILD[decor[t]]["cost"] * 0.5
		decor.erase(t)
	elif grid.get(t, "") == "floor":
		money += Data.BUILD["corridor"]["cost"] * 0.5
		grid.erase(t)
	else:
		var u = unit_at(t)
		if u == null:
			return false
		if u["state"] != "vacant":
			notify.emit("You can only bulldoze empty shop units.", "bad")
			return false
		money += Data.BUILD["unit"]["cost"] * 0.5
		units.erase(u)
		unit_changed.emit(u["id"])
	rebuild_paths()
	tiles_changed.emit()
	changed.emit()
	return true


func walkable(t: Vector2i) -> bool:
	return grid.has(t) and not decor.has(t)


func rebuild_paths() -> void:
	astar.fill_solid_region(astar.region, true)
	for t in grid:
		if not decor.has(t):
			astar.set_point_solid(t, false)


func entrance_tile() -> Vector2i:
	for t in grid:
		if grid[t] == "entrance":
			return t
	return Vector2i(Data.GRID_W / 2, Data.GRID_H - 1)


func find_path(from: Vector2i, to: Vector2i) -> Array:
	if not in_bounds(from) or not in_bounds(to):
		return []
	if astar.is_point_solid(from) or astar.is_point_solid(to):
		return []
	return Array(astar.get_id_path(from, to))


func door_reachable(u: Dictionary) -> bool:
	var d := door_tile(u["pos"], u["rot"])
	if not walkable(d):
		return false
	return find_path(entrance_tile(), d).size() > 0


func total_appeal() -> float:
	var a := 0.0
	for t in decor:
		a += Data.BUILD[decor[t]].get("appeal", 0.0)
	return a


## Appeal of decorations close to a tile (used for shopper mood).
func appeal_near(t: Vector2i, radius: int = 3) -> float:
	var a := 0.0
	for d in decor:
		if absi(d.x - t.x) <= radius and absi(d.y - t.y) <= radius:
			a += Data.BUILD[decor[d]].get("appeal", 0.0)
	return a


# ===========================================================================
# Money helpers
# ===========================================================================

func _pay(amount: float, category: String) -> bool:
	if money < amount:
		notify.emit("Not enough money! You need %s." % Data.money_str(amount), "bad")
		return false
	money -= amount
	if category == "build":
		today["build"] += amount
	else:
		today["expenses"] += amount
	changed.emit()
	return true


func take_loan(amount: float) -> void:
	if loan + amount > max_loan():
		notify.emit("The bank won't lend you more than %s in total." % Data.money_str(max_loan()), "bad")
		return
	loan += amount
	money += amount
	notify.emit("You borrowed %s. Interest is 1%% per day." % Data.money_str(amount), "info")
	changed.emit()


func repay_loan(amount: float) -> void:
	amount = minf(amount, loan)
	if amount <= 0:
		return
	if money < amount:
		notify.emit("Not enough money to repay that much.", "bad")
		return
	loan -= amount
	money -= amount
	notify.emit("Repaid %s of your loan." % Data.money_str(amount), "good")
	changed.emit()


func max_loan() -> float:
	return 20000.0 + level * 10000.0 + rating * 5000.0


const MARKETING := {
	"flyers": {"name": "Flyers", "cost": 600, "mult": 1.2, "days": 3},
	"radio": {"name": "Radio Ad", "cost": 2500, "mult": 1.45, "days": 4},
	"tv": {"name": "TV Commercial", "cost": 9000, "mult": 1.9, "days": 5},
}


func buy_marketing(kind: String) -> void:
	var m: Dictionary = MARKETING[kind]
	for active in marketing:
		if active["name"] == m["name"]:
			notify.emit("That campaign is already running.", "bad")
			return
	if _pay(m["cost"], "expense"):
		marketing.append({"name": m["name"], "mult": m["mult"], "days": m["days"]})
		notify.emit("%s campaign started! More shoppers for %d days." % [m["name"], m["days"]], "good")
		changed.emit()


func hire(kind: String, delta: int) -> void:
	if kind == "cleaner":
		cleaners = maxi(0, cleaners + delta)
	elif kind == "security":
		security = maxi(0, security + delta)
	changed.emit()


# ===========================================================================
# Tenants
# ===========================================================================

func _random_type(max_level: int = 99) -> String:
	var keys := []
	for k in Data.SHOP_TYPES:
		if Data.SHOP_TYPES[k]["level"] <= max_level:
			keys.append(k)
	return keys[randi() % keys.size()]


func _make_applicant(type: String = "") -> Dictionary:
	# Chain stores apply only when the mall is good enough.
	if type == "" and randf() < 0.25:
		var options := []
		for c in Data.CHAINS:
			if rating >= c["min_rating"] and not _has_tenant_named(c["name"]):
				options.append(c)
		if options.size() > 0:
			var c: Dictionary = options[randi() % options.size()]
			var spend: float = Data.SHOP_TYPES[c["type"]]["spend"]
			return {
				"name": c["name"], "type": c["type"], "rent": roundf((spend * 2.0 + 25.0) * 1.7 * (0.8 + rating * 0.12)),
				"reliability": 0.98, "chain": true, "happiness": 70.0, "sales_today": 0.0, "sales_yday": 0.0,
				"visits_today": 0, "owed": 0.0, "days": 0, "expires": 3,
			}
	if type == "":
		type = _random_type(level + 1)
	var names: Array = Data.TENANT_NAMES[type]
	var nm: String = names[randi() % names.size()]
	var t_spend: float = Data.SHOP_TYPES[type]["spend"]
	var rent := roundf((t_spend * 2.0 + 25.0) * (0.7 + rating * 0.12) * randf_range(0.85, 1.2))
	return {
		"name": nm, "type": type, "rent": rent, "reliability": randf_range(0.6, 0.97), "chain": false,
		"happiness": 60.0, "sales_today": 0.0, "sales_yday": 0.0, "visits_today": 0, "owed": 0.0,
		"days": 0, "expires": 3,
	}


func _has_tenant_named(n: String) -> bool:
	for u in units:
		if u["state"] == "tenant" and u["tenant"]["name"] == n:
			return true
	return false


func lease_unit(u: Dictionary, applicant_index: int) -> void:
	if u["state"] != "vacant" or applicant_index < 0 or applicant_index >= applicants.size():
		return
	var a: Dictionary = applicants[applicant_index]
	applicants.remove_at(applicant_index)
	a.erase("expires")
	u["state"] = "tenant"
	u["tenant"] = a
	notify.emit("%s signed a lease for %s/day." % [a["name"], Data.money_str(a["rent"])], "good")
	unit_changed.emit(u["id"])
	changed.emit()


func evict(u: Dictionary) -> void:
	if u["state"] != "tenant":
		return
	var t: Dictionary = u["tenant"]
	notify.emit("You evicted %s." % t["name"], "info")
	u["state"] = "vacant"
	u["tenant"] = null
	_drop_requests_for(u["id"])
	unit_changed.emit(u["id"])
	changed.emit()


func change_rent(u: Dictionary, delta: float) -> void:
	if u["state"] != "tenant":
		return
	var t: Dictionary = u["tenant"]
	var old: float = t["rent"]
	t["rent"] = maxf(10.0, old + delta)
	if delta > 0:
		t["happiness"] = clampf(t["happiness"] - 6.0, 0.0, 100.0)
	else:
		t["happiness"] = clampf(t["happiness"] + 4.0, 0.0, 100.0)
	changed.emit()


func answer_request(index: int, accept: bool) -> void:
	if index < 0 or index >= requests.size():
		return
	var r: Dictionary = requests[index]
	requests.remove_at(index)
	var u = unit_by_id(int(r["unit"]))
	if u != null and u["state"] == "tenant":
		var t: Dictionary = u["tenant"]
		if accept:
			t["rent"] = roundf(t["rent"] * 0.8)
			t["happiness"] = clampf(t["happiness"] + 25.0, 0.0, 100.0)
			notify.emit("%s thanks you for the rent cut." % t["name"], "good")
		else:
			t["happiness"] = clampf(t["happiness"] - 10.0, 0.0, 100.0)
			notify.emit("%s is unhappy you said no." % t["name"], "bad")
	changed.emit()


func _drop_requests_for(unit_id: int) -> void:
	var keep := []
	for r in requests:
		if int(r["unit"]) != unit_id:
			keep.append(r)
	requests = keep


# ===========================================================================
# Owned shops
# ===========================================================================

const SHELF_CAP := 24
const SHOP_SETUP_COST := 1500


func owned_count() -> int:
	var n := 0
	for u in units:
		if u["state"] == "owned":
			n += 1
	return n


func can_open_own_shop() -> bool:
	return owned_count() < Data.max_owned_shops(level)


func open_own_shop(u: Dictionary, type: String) -> void:
	if u["state"] != "vacant":
		return
	if not can_open_own_shop():
		notify.emit("Reach a higher owner level to run more shops yourself.", "bad")
		return
	if Data.SHOP_TYPES[type]["level"] > level:
		notify.emit("You need owner level %d for that shop type." % Data.SHOP_TYPES[type]["level"], "bad")
		return
	if not _pay(SHOP_SETUP_COST, "build"):
		return
	var shelves := []
	for i in 4:
		shelves.append({"p": i, "stock": 10})
	u["state"] = "owned"
	u["shop"] = {
		"type": type, "price_mult": 1.0, "shelves": shelves, "back": [20, 20, 20, 20], "orders": [],
		"cashier": false, "stocker": false, "sales_today": 0.0, "sales_yday": 0.0,
		"customers_today": 0, "lost_today": 0,
	}
	notify.emit("You opened your own %s! Order stock and keep the shelves full." % Data.SHOP_TYPES[type]["name"], "good")
	unit_changed.emit(u["id"])
	changed.emit()


func close_own_shop(u: Dictionary) -> void:
	if u["state"] != "owned":
		return
	u["state"] = "vacant"
	u["shop"] = null
	notify.emit("You closed your shop.", "info")
	unit_changed.emit(u["id"])
	changed.emit()


func product(u: Dictionary, p: int) -> Array:
	return Data.SHOP_TYPES[u["shop"]["type"]]["products"][p]


func product_price(u: Dictionary, p: int) -> float:
	return product(u, p)[2] * u["shop"]["price_mult"]


func order_stock(u: Dictionary, p: int, qty: int) -> void:
	var cost: float = product(u, p)[1] * qty
	if not _pay(cost, "expense"):
		return
	today["own_cost"] += cost
	u["shop"]["orders"].append({"p": p, "qty": qty, "at": minute + 60.0})
	notify.emit("Ordered %d x %s. Arrives in about an hour." % [qty, product(u, p)[0]], "info")
	changed.emit()


## Move items from the back room onto a shelf. Returns how many were moved.
func restock_shelf(u: Dictionary, shelf_index: int) -> int:
	var s: Dictionary = u["shop"]
	var sh: Dictionary = s["shelves"][shelf_index]
	var p: int = sh["p"]
	var room: int = SHELF_CAP - int(sh["stock"])
	var n := mini(room, int(s["back"][p]))
	if n <= 0:
		return 0
	sh["stock"] = int(sh["stock"]) + n
	s["back"][p] = int(s["back"][p]) - n
	changed.emit()
	return n


func cycle_shelf_product(u: Dictionary, shelf_index: int) -> void:
	var s: Dictionary = u["shop"]
	var sh: Dictionary = s["shelves"][shelf_index]
	# put current stock back into the back room
	s["back"][int(sh["p"])] = int(s["back"][int(sh["p"])]) + int(sh["stock"])
	sh["stock"] = 0
	sh["p"] = (int(sh["p"]) + 1) % 4
	changed.emit()


func set_price_mult(u: Dictionary, v: float) -> void:
	u["shop"]["price_mult"] = clampf(snappedf(v, 0.05), 0.5, 2.5)
	changed.emit()


func toggle_staff(u: Dictionary, kind: String) -> void:
	u["shop"][kind] = not u["shop"][kind]
	changed.emit()


## A shopper takes one item from a shelf. Returns false if it is empty.
func take_item(u: Dictionary, shelf_index: int) -> bool:
	var sh: Dictionary = u["shop"]["shelves"][shelf_index]
	if int(sh["stock"]) <= 0:
		return false
	sh["stock"] = int(sh["stock"]) - 1
	return true


func return_item(u: Dictionary, shelf_index: int) -> void:
	if u["state"] != "owned":
		return
	var sh: Dictionary = u["shop"]["shelves"][shelf_index]
	sh["stock"] = mini(SHELF_CAP, int(sh["stock"]) + 1)


func own_sale(u: Dictionary, amount: float) -> void:
	money += amount
	u["shop"]["sales_today"] += amount
	u["shop"]["customers_today"] += 1
	today["own_sales"] += amount
	best_own_sales = maxf(best_own_sales, today["own_sales"])


func tenant_sale(u: Dictionary, amount: float) -> void:
	var t: Dictionary = u["tenant"]
	t["sales_today"] += amount
	today["tenant_sales"] += amount


# ===========================================================================
# Shoppers
# ===========================================================================

func expected_visitors() -> float:
	var open_shops := 0
	for u in units:
		if u["state"] != "vacant" and door_reachable(u):
			open_shops += 1
	var v := 12.0 + 9.0 * open_shops + total_appeal() * 0.8
	v *= 0.5 + rating * 0.3
	for m in marketing:
		v *= m["mult"]
	v *= {"Spring": 1.0, "Summer": 1.1, "Autumn": 0.95, "Winter": 1.05}[season()]
	if season() == "Winter" and day_of_season() >= 5:
		v *= 1.6  # holiday rush
	v *= rival_multiplier()
	return v


func rival_multiplier() -> float:
	if rival_strength <= 0.0:
		return 1.0
	return clampf(1.0 - (rival_strength - rating) * 0.15, 0.55, 1.1)


func shopper_arrived() -> void:
	today["visitors"] += 1
	best_visitors = maxi(best_visitors, int(today["visitors"]))
	var bins := 0
	for t in decor:
		if decor[t] == "bin":
			bins += 1
	dirt = clampf(dirt + 0.25 / (1.0 + bins * 0.25), 0.0, 100.0)


func shopper_left(satisfaction: float, complaint: String) -> void:
	today["sat_sum"] += clampf(satisfaction, 0.0, 1.0)
	today["sat_count"] += 1
	if complaint != "":
		today["complaints"][complaint] = int(today["complaints"].get(complaint, 0)) + 1


# ===========================================================================
# End of day
# ===========================================================================

func end_day() -> void:
	running = false
	var report := {"day": day, "lines": [], "events": []}
	var income := 0.0
	var costs := 0.0

	# Rent from tenants
	var rent_total := 0.0
	var leaving := []
	for u in units:
		if u["state"] != "tenant":
			continue
		var t: Dictionary = u["tenant"]
		var due: float = t["rent"] + t["owed"]
		if randf() < (1.0 - t["reliability"]) * 0.6:
			t["owed"] = due
			report["events"].append("%s paid rent late (owes %s)." % [t["name"], Data.money_str(due)])
		else:
			rent_total += due
			t["owed"] = 0.0
		# happiness: did they sell enough to comfortably cover rent?
		var needed: float = t["rent"] * 2.2
		var hd := clampf((t["sales_today"] / maxf(needed, 1.0) - 1.0) * 10.0, -6.0, 6.0)
		hd += (rating - 2.0) * 0.8
		hd -= dirt / 40.0
		if trend_type == t["type"]:
			hd += 2.0
		t["happiness"] = clampf(t["happiness"] + hd, 0.0, 100.0)
		t["sales_yday"] = t["sales_today"]
		t["sales_today"] = 0.0
		t["visits_today"] = 0
		t["days"] = int(t["days"]) + 1
		if t["happiness"] < 12.0:
			leaving.append(u)
		elif t["happiness"] < 30.0 and randf() < 0.35 and not _has_request(u["id"]):
			requests.append({"unit": u["id"], "text": "%s is struggling and asks for a 20%% rent cut." % t["name"]})
	for u in leaving:
		report["events"].append("%s was unhappy and moved out!" % u["tenant"]["name"])
		u["state"] = "vacant"
		u["tenant"] = null
		_drop_requests_for(u["id"])
		unit_changed.emit(u["id"])
	money += rent_total
	income += rent_total
	report["lines"].append(["Rent from tenants", rent_total])

	var own := 0.0
	for u in units:
		if u["state"] == "owned":
			own += u["shop"]["sales_today"]
	report["lines"].append(["Your shop sales", own])
	income += own
	report["lines"].append(["Stock bought", -today["own_cost"]])
	costs += today["own_cost"]

	# Wages
	var wages := cleaners * Data.CLEANER_WAGE + security * Data.SECURITY_WAGE
	for u in units:
		if u["state"] == "owned":
			var s: Dictionary = u["shop"]
			if s["cashier"]:
				wages += Data.CASHIER_WAGE
			if s["stocker"]:
				wages += Data.STOCKER_WAGE
			s["sales_yday"] = s["sales_today"]
			s["sales_today"] = 0.0
			s["customers_today"] = 0
			s["lost_today"] = 0
	money -= wages
	costs += wages
	report["lines"].append(["Staff wages", -wages])

	# Upkeep
	var upkeep := units.size() * 18.0 + grid.size() * 2.0 + decor.size() * 1.0
	money -= upkeep
	costs += upkeep
	report["lines"].append(["Building upkeep", -upkeep])

	var interest := roundf(loan * 0.01)
	if interest > 0:
		money -= interest
		costs += interest
		report["lines"].append(["Loan interest", -interest])

	var other_spend: float = today["expenses"] - today["own_cost"]
	if other_spend > 0:
		report["lines"].append(["Marketing & other", -other_spend])
		costs += other_spend
	if today["build"] > 0:
		report["lines"].append(["Construction", -today["build"]])
		costs += today["build"]

	# Random events
	_random_event(report)

	# Rating moves toward a target based on how the day went
	var avg_sat := 0.5
	if today["sat_count"] > 0:
		avg_sat = today["sat_sum"] / today["sat_count"]
	var types := {}
	var occupied := 0
	for u in units:
		if u["state"] == "tenant":
			types[u["tenant"]["type"]] = true
			occupied += 1
		elif u["state"] == "owned":
			types[u["shop"]["type"]] = true
			occupied += 1
	var target := avg_sat * 3.0
	target += minf(1.0, types.size() / 8.0)
	target += minf(0.8, total_appeal() / 30.0)
	if units.size() > 0:
		target += 0.4 * float(occupied) / units.size()
	target -= dirt / 100.0 * 1.5
	# a small mall can't be a 5-star mall: size caps the rating
	target = clampf(target, 0.3, minf(5.0, 1.6 + units.size() * 0.24))
	var old_rating := rating
	rating = clampf(lerpf(rating, target, 0.3), 0.0, 5.0)
	report["rating_old"] = old_rating
	report["rating"] = rating
	report["satisfaction"] = avg_sat
	report["visitors"] = today["visitors"]
	report["complaints"] = today["complaints"]

	# Marketing countdown
	var still := []
	for m in marketing:
		m["days"] = int(m["days"]) - 1
		if m["days"] > 0:
			still.append(m)
	marketing = still

	# New applicants, old ones give up
	var keep := []
	for a in applicants:
		a["expires"] = int(a["expires"]) - 1
		if a["expires"] > 0:
			keep.append(a)
	applicants = keep
	var n_new := randi_range(1, 3)
	for i in n_new:
		if applicants.size() < 6:
			applicants.append(_make_applicant())

	# XP for a profitable day
	var profit: float = money - today["start_money"]
	report["profit"] = profit
	if profit > 0:
		add_xp(mini(60, int(profit / 80.0)))

	# Season change brings a new trend; a rival mall shows up eventually
	if day % Data.DAYS_PER_SEASON == 0:
		var old_trend := trend_type
		while trend_type == old_trend:
			trend_type = _random_type()
		report["events"].append("New season! %s shops are trending." % Data.SHOP_TYPES[trend_type]["name"])
	if day == 12:
		rival_strength = 2.5
		report["events"].append("A rival mall, Sunset Plaza, opened across town. Keep your rating up or lose shoppers!")
	elif rival_strength > 0:
		rival_strength = minf(4.6, rival_strength + 0.04)

	# Bankruptcy check
	if money < 0:
		debt_days += 1
		if debt_days >= Data.BANKRUPT_DAYS:
			report["bankrupt"] = true
		else:
			report["events"].append("WARNING: You're in debt! %d more day(s) like this and you go bankrupt." % (Data.BANKRUPT_DAYS - debt_days))
	else:
		debt_days = 0

	report["income"] = income
	report["costs"] = costs
	report["money"] = money
	history.append({"day": day, "profit": profit, "visitors": today["visitors"], "rating": rating})
	if history.size() > 30:
		history.pop_front()

	check_goals()
	changed.emit()
	day_ended.emit(report)
	if report.get("bankrupt", false):
		is_over = true
		delete_save()
		game_over.emit("You were in debt for %d days in a row. The bank took your mall." % Data.BANKRUPT_DAYS)


func _has_request(unit_id: int) -> bool:
	for r in requests:
		if int(r["unit"]) == unit_id:
			return true
	return false


func _random_event(report: Dictionary) -> void:
	if randf() > 0.35:
		return
	var roll := randi() % 6
	match roll:
		0:
			var cost := roundf(randf_range(300, 1200))
			money -= cost
			report["events"].append("A pipe burst! Repairs cost %s." % Data.money_str(cost))
		1:
			marketing.append({"name": "Viral Post", "mult": 1.35, "days": 2})
			report["events"].append("Someone posted your mall online and it went viral! More shoppers coming.")
		2:
			if dirt > 45:
				money -= 1000
				report["events"].append("A health inspector found the mall dirty. Fined $1,000. Hire cleaners!")
			else:
				add_xp(30)
				report["events"].append("A health inspector visited and was impressed. +30 XP")
		3:
			var theft := 0.0
			for u in units:
				if u["state"] == "owned" and randf() > security * 0.35:
					theft += roundf(randf_range(40, 250))
			if theft > 0:
				money -= theft
				report["events"].append("Shoplifters stole %s from your shops. Security guards help." % Data.money_str(theft))
		4:
			var cost2 := roundf(randf_range(150, 600))
			money -= cost2
			report["events"].append("Power outage! Generator rental cost %s." % Data.money_str(cost2))
		5:
			marketing.append({"name": "Celebrity Visit", "mult": 1.5, "days": 1})
			report["events"].append("A celebrity is visiting tomorrow! Expect a crowd.")


func start_next_day() -> void:
	if is_over:
		return
	day += 1
	minute = Data.OPEN_MINUTE - 30
	_reset_today()
	running = true
	save_game()
	day_started.emit()
	changed.emit()


# ===========================================================================
# XP, levels, goals
# ===========================================================================

func add_xp(amount: int) -> void:
	xp += amount
	var new_level := Data.level_for_xp(xp)
	if new_level > level:
		level = new_level
		notify.emit("Level up! You're now owner level %d. You can run %d shop(s) yourself." % [level, Data.max_owned_shops(level)], "good")
		level_up.emit(level)
	changed.emit()


func goal(i: int) -> Dictionary:
	if i < Data.GOALS.size():
		return Data.GOALS[i]
	# endless goals once the list is done
	var n := i - Data.GOALS.size()
	var kinds := ["visitors", "own_sales", "money", "tenants"]
	var kind: String = kinds[n % kinds.size()]
	var step := n / kinds.size() + 1
	match kind:
		"visitors":
			return {"text": "Get %d visitors in one day" % (300 + step * 80), "kind": kind, "target": 300 + step * 80, "cash": 10000 * step, "xp": 300}
		"own_sales":
			return {"text": "Sell %s in your shops in one day" % Data.money_str(3000 + step * 1500), "kind": kind, "target": 3000 + step * 1500, "cash": 8000 * step, "xp": 300}
		"money":
			return {"text": "Reach %s in the bank" % Data.money_str(250000 + step * 150000), "kind": kind, "target": 250000 + step * 150000, "cash": 0, "xp": 400}
		_:
			return {"text": "Have %d tenants at once" % (10 + step * 2), "kind": kind, "target": 10 + step * 2, "cash": 8000 * step, "xp": 300}


func active_goals() -> Array:
	var out := []
	var i := 0
	while out.size() < 3 and i < 500:
		if not completed_goals.has(i):
			out.append(i)
		i += 1
	return out


func goal_progress(g: Dictionary) -> float:
	match g["kind"]:
		"tenants":
			var n := 0
			for u in units:
				if u["state"] == "tenant":
					n += 1
			return n
		"owned":
			return owned_count()
		"visitors":
			return best_visitors
		"decor":
			return decor.size()
		"own_sales":
			return best_own_sales
		"units":
			return units.size()
		"rating":
			return snappedf(rating, 0.1)
		"cleaners":
			return cleaners
		"money":
			return money
		"chains":
			var c := 0
			for u in units:
				if u["state"] == "tenant" and u["tenant"]["chain"]:
					c += 1
			return c
	return 0.0


func check_goals() -> void:
	for i in active_goals():
		var g := goal(i)
		if goal_progress(g) >= g["target"]:
			completed_goals.append(i)
			money += g["cash"]
			var reward := "+%d XP" % g["xp"]
			if g["cash"] > 0:
				reward = "%s and %s" % [Data.money_str(g["cash"]), reward]
			notify.emit("Goal complete: %s! You got %s." % [g["text"], reward], "good")
			add_xp(g["xp"])
			changed.emit()
