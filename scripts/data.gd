class_name Data
## Static game data: shop types, products, tenant names, build items and goals.

const TILE := 2.0          # meters per grid tile
const GRID_W := 30
const GRID_H := 22
const UNIT_SIZE := 3       # shop units are 3x3 tiles

const OPEN_MINUTE := 9 * 60
const CLOSE_MINUTE := 21 * 60

const START_MONEY := 25000
const BANKRUPT_DAYS := 3   # days in a row ending with negative money -> game over

# Build items. cost is in dollars. level = owner level needed.
const BUILD := {
	"corridor": {"name": "Floor", "cost": 100, "level": 1},
	"unit": {"name": "Shop Unit", "cost": 7500, "level": 1},
	"bench": {"name": "Bench", "cost": 250, "level": 1, "appeal": 1.0},
	"plant": {"name": "Plant", "cost": 150, "level": 1, "appeal": 0.8},
	"bin": {"name": "Trash Bin", "cost": 120, "level": 1, "appeal": 0.5},
	"lamp": {"name": "Lamp", "cost": 400, "level": 2, "appeal": 1.2},
	"fountain": {"name": "Fountain", "cost": 3500, "level": 3, "appeal": 4.0},
}

const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]
const DAYS_PER_SEASON := 7

# Shop types. spend = average purchase at a tenant shop.
# products: [name, wholesale cost, suggested price]
const SHOP_TYPES := {
	"clothing": {
		"name": "Clothing", "color": Color(0.85, 0.35, 0.45), "spend": 38.0, "level": 1,
		"products": [["T-Shirt", 6.0, 16.0], ["Jeans", 14.0, 36.0], ["Hoodie", 12.0, 30.0], ["Sneakers", 24.0, 58.0]],
	},
	"cafe": {
		"name": "Cafe", "color": Color(0.6, 0.4, 0.25), "spend": 9.0, "level": 1,
		"products": [["Coffee", 1.0, 4.5], ["Muffin", 1.2, 3.5], ["Sandwich", 2.8, 8.0], ["Smoothie", 1.8, 6.0]],
	},
	"books": {
		"name": "Bookstore", "color": Color(0.3, 0.5, 0.75), "spend": 18.0, "level": 1,
		"products": [["Novel", 6.0, 15.0], ["Comic", 3.0, 8.0], ["Magazine", 1.5, 5.0], ["Cookbook", 9.0, 24.0]],
	},
	"toys": {
		"name": "Toy Store", "color": Color(0.95, 0.7, 0.2), "spend": 22.0, "level": 1,
		"products": [["Plush", 5.0, 15.0], ["Puzzle", 6.0, 17.0], ["Action Figure", 8.0, 22.0], ["Board Game", 14.0, 35.0]],
	},
	"electronics": {
		"name": "Electronics", "color": Color(0.25, 0.75, 0.8), "spend": 70.0, "level": 2,
		"products": [["Phone Case", 3.0, 14.0], ["Headphones", 22.0, 55.0], ["Charger", 4.0, 18.0], ["Game Console", 190.0, 320.0]],
	},
	"food": {
		"name": "Burger Joint", "color": Color(0.9, 0.45, 0.15), "spend": 12.0, "level": 2,
		"products": [["Burger", 2.5, 8.0], ["Fries", 0.6, 3.5], ["Soda", 0.4, 2.5], ["Milkshake", 1.2, 5.0]],
	},
	"sports": {
		"name": "Sports Gear", "color": Color(0.35, 0.7, 0.35), "spend": 45.0, "level": 3,
		"products": [["Football", 8.0, 25.0], ["Yoga Mat", 7.0, 22.0], ["Running Shoes", 30.0, 80.0], ["Water Bottle", 2.0, 10.0]],
	},
	"jewelry": {
		"name": "Jewelry", "color": Color(0.7, 0.45, 0.85), "spend": 120.0, "level": 4,
		"products": [["Bracelet", 18.0, 55.0], ["Ring", 60.0, 170.0], ["Necklace", 80.0, 220.0], ["Watch", 120.0, 310.0]],
	},
}

const TENANT_NAMES := {
	"clothing": ["Urban Thread", "Denim Depot", "StyleHub", "Cotton & Co.", "Velvet Lane"],
	"cafe": ["Bean There", "Daily Grind", "Brew Bros", "Mocha Moon", "Cup & Saucer"],
	"books": ["Page Turner", "Ink Well Books", "Chapter One", "Dusty Shelves"],
	"toys": ["Toy Box", "Fun Factory", "Tiny Giants", "Playtime Palace"],
	"electronics": ["ByteShop", "Circuit City", "GadgetZone", "Pixel Point"],
	"food": ["Big Bun Burgers", "Grill Master", "Patty Shack", "Fry Day"],
	"sports": ["Peak Sports", "GoalLine", "FitGear", "Trail Blazer"],
	"jewelry": ["Golden Hour", "Sparkle & Stone", "Diamond Row", "Silver Leaf"],
}

# Big chain stores only move in when the mall rating is high enough.
const CHAINS := [
	{"name": "MegaThreads", "type": "clothing", "min_rating": 3.0},
	{"name": "StarBean Coffee", "type": "cafe", "min_rating": 2.5},
	{"name": "TechWorld", "type": "electronics", "min_rating": 3.5},
	{"name": "BurgerKingdom", "type": "food", "min_rating": 3.0},
	{"name": "Lux Jewels", "type": "jewelry", "min_rating": 4.0},
]

# Owner level thresholds (total XP needed for each level).
const LEVEL_XP := [0, 100, 300, 650, 1100, 1700, 2500, 3500, 4800, 6500]

# Staff wages per day.
const CASHIER_WAGE := 110
const STOCKER_WAGE := 90
const CLEANER_WAGE := 80
const SECURITY_WAGE := 100

# Career goals. Checked continuously; finished in order, 3 active at a time.
# kind: what to measure; target: number to reach.
const GOALS := [
	{"text": "Lease 3 shop units to tenants", "kind": "tenants", "target": 3, "cash": 1500, "xp": 60},
	{"text": "Open your own shop", "kind": "owned", "target": 1, "cash": 1000, "xp": 60},
	{"text": "Get 40 visitors in one day", "kind": "visitors", "target": 40, "cash": 1500, "xp": 60},
	{"text": "Place 6 decorations", "kind": "decor", "target": 6, "cash": 800, "xp": 40},
	{"text": "Sell $500 in your shops in one day", "kind": "own_sales", "target": 500, "cash": 2000, "xp": 80},
	{"text": "Build a new shop unit", "kind": "units", "target": 5, "cash": 2000, "xp": 60},
	{"text": "Reach a 2-star mall rating", "kind": "rating", "target": 2.0, "cash": 3000, "xp": 100},
	{"text": "Have 5 tenants at once", "kind": "tenants", "target": 5, "cash": 3000, "xp": 100},
	{"text": "Get 100 visitors in one day", "kind": "visitors", "target": 100, "cash": 4000, "xp": 120},
	{"text": "Hire a cleaner", "kind": "cleaners", "target": 1, "cash": 500, "xp": 40},
	{"text": "Reach $50,000 in the bank", "kind": "money", "target": 50000, "cash": 0, "xp": 150},
	{"text": "Run 2 of your own shops", "kind": "owned", "target": 2, "cash": 4000, "xp": 150},
	{"text": "Reach a 3-star mall rating", "kind": "rating", "target": 3.0, "cash": 8000, "xp": 200},
	{"text": "Sign a big chain store", "kind": "chains", "target": 1, "cash": 5000, "xp": 200},
	{"text": "Have 10 tenants at once", "kind": "tenants", "target": 10, "cash": 8000, "xp": 250},
	{"text": "Get 250 visitors in one day", "kind": "visitors", "target": 250, "cash": 10000, "xp": 300},
	{"text": "Sell $3,000 in your shops in one day", "kind": "own_sales", "target": 3000, "cash": 8000, "xp": 300},
	{"text": "Reach a 4-star mall rating", "kind": "rating", "target": 4.0, "cash": 20000, "xp": 400},
	{"text": "Reach $250,000 in the bank", "kind": "money", "target": 250000, "cash": 0, "xp": 500},
	{"text": "Reach a 5-star mall rating", "kind": "rating", "target": 4.9, "cash": 50000, "xp": 800},
]

const SHOPPER_NAMES := ["Alex", "Sam", "Jordan", "Taylor", "Riley", "Casey", "Morgan", "Jamie", "Drew", "Quinn",
	"Avery", "Parker", "Reese", "Rowan", "Skyler", "Emery", "Kai", "Logan", "Noa", "Remy"]


static func max_owned_shops(level: int) -> int:
	return clampi(1 + (level - 1) / 2, 1, 5)


static func level_for_xp(xp: int) -> int:
	var lvl := 1
	for i in LEVEL_XP.size():
		if xp >= LEVEL_XP[i]:
			lvl = i + 1
	return lvl


static func money_str(v: float) -> String:
	var neg := v < 0
	var s := str(int(round(absf(v))))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if neg else "$") + out


static func time_str(minute: float) -> String:
	var m := int(minute)
	return "%02d:%02d" % [m / 60, m % 60]
