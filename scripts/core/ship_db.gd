class_name ShipDB
## Static game data: hull classes, upgrade tracks, enemy templates and bounties.
## Distances in meters, speeds in m/s. ShipDB.build_stats() converts to pixels.

const HULLS := {
	# --- Player-purchasable hulls -------------------------------------------------
	"sloop": {
		"name": "Sloop", "player": true, "cost": 0, "tier": 1,
		"desc": "Fast flanker. Light hull, quick rudder, small crew.",
		"length": 14.0, "beam": 5.0, "freeboard": 3.2, "masts": 1, "style": "sloop",
		"hp": 110.0, "armor": 0.05, "max_speed": 13.0, "turn_rate": 1.9, "angular_drag": 2.6,
		"linear_drag": 0.45, "keel_grip": 3.2, "min_rudder": 0.1,
		"cannons": 2, "max_cannons": 3, "reload": 3.0, "damage": 11.0, "range": 48.0,
		"muzzle_speed": 52.0, "crew": 14, "hold": 6, "mass": 1.0, "threat": 0.85, "ram": 1.0,
	},
	"brigantine": {
		"name": "Brigantine", "player": true, "cost": 700, "tier": 2,
		"desc": "Balanced two-master. Solid broadsides, decent speed.",
		"length": 20.0, "beam": 6.5, "freeboard": 4.0, "masts": 2, "style": "brig",
		"hp": 190.0, "armor": 0.12, "max_speed": 11.5, "turn_rate": 1.45, "angular_drag": 2.5,
		"linear_drag": 0.42, "keel_grip": 3.4, "min_rudder": 0.1,
		"cannons": 3, "max_cannons": 4, "reload": 3.3, "damage": 12.5, "range": 52.0,
		"muzzle_speed": 54.0, "crew": 22, "hold": 10, "mass": 1.8, "threat": 1.0, "ram": 1.1,
	},
	"galley": {
		"name": "Ironclad War Galley", "player": true, "cost": 1400, "tier": 3,
		"desc": "Armored tank with oars and a bronze ram. Draws enemy fire.",
		"length": 24.0, "beam": 8.0, "freeboard": 3.6, "masts": 1, "style": "galley",
		"hp": 360.0, "armor": 0.32, "max_speed": 9.5, "turn_rate": 1.2, "angular_drag": 2.4,
		"linear_drag": 0.40, "keel_grip": 3.8, "min_rudder": 0.4,
		"cannons": 3, "max_cannons": 4, "reload": 3.6, "damage": 12.0, "range": 46.0,
		"muzzle_speed": 50.0, "crew": 36, "hold": 12, "mass": 3.0, "threat": 1.7, "ram": 2.2,
	},
	"frigate": {
		"name": "Frigate", "player": true, "cost": 2100, "tier": 4,
		"desc": "Three-masted gun platform. Heavy broadsides, long range.",
		"length": 28.0, "beam": 8.0, "freeboard": 5.0, "masts": 3, "style": "frigate",
		"hp": 280.0, "armor": 0.18, "max_speed": 10.8, "turn_rate": 1.15, "angular_drag": 2.3,
		"linear_drag": 0.40, "keel_grip": 3.4, "min_rudder": 0.1,
		"cannons": 4, "max_cannons": 6, "reload": 3.5, "damage": 14.0, "range": 58.0,
		"muzzle_speed": 57.0, "crew": 30, "hold": 14, "mass": 3.2, "threat": 1.1, "ram": 1.2,
	},
	# --- Enemy-only hulls -----------------------------------------------------------
	"fluyt": {
		"name": "Fluyt", "player": false, "cost": 0, "tier": 1,
		"desc": "Round-sterned merchantman.",
		"length": 18.0, "beam": 6.5, "freeboard": 3.8, "masts": 2, "style": "fluyt",
		"hp": 140.0, "armor": 0.08, "max_speed": 8.5, "turn_rate": 1.1, "angular_drag": 2.5,
		"linear_drag": 0.45, "keel_grip": 3.2, "min_rudder": 0.1,
		"cannons": 1, "max_cannons": 2, "reload": 4.5, "damage": 9.0, "range": 42.0,
		"muzzle_speed": 48.0, "crew": 10, "hold": 10, "mass": 1.8, "threat": 1.0, "ram": 0.8,
	},
	"treasure": {
		"name": "Treasure Galleon", "player": false, "cost": 0, "tier": 3,
		"desc": "Slow, rich, and well defended.",
		"length": 27.0, "beam": 9.5, "freeboard": 5.5, "masts": 3, "style": "galleon",
		"hp": 300.0, "armor": 0.2, "max_speed": 7.8, "turn_rate": 0.95, "angular_drag": 2.3,
		"linear_drag": 0.42, "keel_grip": 3.3, "min_rudder": 0.1,
		"cannons": 3, "max_cannons": 4, "reload": 4.0, "damage": 12.0, "range": 48.0,
		"muzzle_speed": 50.0, "crew": 26, "hold": 20, "mass": 3.6, "threat": 1.0, "ram": 1.0,
	},
	"manowar": {
		"name": "Man-o'-War", "player": false, "cost": 0, "tier": 5,
		"desc": "Armada ship of the line.",
		"length": 34.0, "beam": 10.5, "freeboard": 6.5, "masts": 3, "style": "galleon",
		"hp": 520.0, "armor": 0.25, "max_speed": 9.0, "turn_rate": 0.9, "angular_drag": 2.2,
		"linear_drag": 0.40, "keel_grip": 3.5, "min_rudder": 0.1,
		"cannons": 6, "max_cannons": 6, "reload": 3.8, "damage": 15.0, "range": 60.0,
		"muzzle_speed": 58.0, "crew": 60, "hold": 16, "mass": 5.0, "threat": 1.0, "ram": 1.4,
	},
}

const PLAYER_HULL_ORDER: Array[String] = ["sloop", "brigantine", "galley", "frigate"]

# Upgrade tracks (spec step 5: Hull Strength, Cannon Count, Sail Speed, Ramming Damage + extras)
const UPGRADES := [
	{"id": "hull", "name": "Hull Strength", "max": 5, "base_cost": 140, "desc": "+15% hull HP, +3% armor"},
	{"id": "cannons", "name": "Cannon Count", "max": 3, "base_cost": 260, "desc": "+1 cannon per broadside (hull limit)"},
	{"id": "sails", "name": "Sail Speed", "max": 5, "base_cost": 140, "desc": "+8% top speed and acceleration"},
	{"id": "ram", "name": "Ramming Damage", "max": 4, "base_cost": 110, "desc": "+50% ram damage, reinforced bow"},
	{"id": "gunnery", "name": "Heavy Shot", "max": 5, "base_cost": 170, "desc": "+12% cannon damage"},
	{"id": "reload", "name": "Gun Drills", "max": 5, "base_cost": 170, "desc": "-8% broadside reload time"},
	{"id": "crew", "name": "Crew Quarters", "max": 4, "base_cost": 120, "desc": "+20% crew (boarding strength)"},
	{"id": "chaser", "name": "Bow Chaser", "max": 2, "base_cost": 300, "desc": "Forward chaser cannon (Lv2: twin)"},
]

const REPAIR_COST_PER_HP := 0.7
const REPAIR_KIT_COST := 60
const MAX_REPAIR_KITS := 3

# Enemy templates. gold = treasury reward on sinking (boarding pays 2x).
const ENEMIES := {
	"cutter": {"hull": "sloop", "name": "Armada Cutter", "gold": 45, "crates": 1, "cannons": 2,
		"hp_mult": 0.85, "dmg_mult": 0.8, "reload_mult": 1.2, "role": "escort", "crew": 12},
	"brig": {"hull": "brigantine", "name": "Armada Brig", "gold": 90, "crates": 2, "cannons": 3,
		"hp_mult": 0.9, "dmg_mult": 0.85, "reload_mult": 1.15, "role": "escort", "crew": 20},
	"frigate": {"hull": "frigate", "name": "Armada Frigate", "gold": 160, "crates": 3, "cannons": 4,
		"hp_mult": 0.9, "dmg_mult": 0.85, "reload_mult": 1.1, "role": "escort", "crew": 28},
	"manowar": {"hull": "manowar", "name": "Armada Man-o'-War", "gold": 300, "crates": 4, "cannons": 5,
		"hp_mult": 0.9, "dmg_mult": 0.85, "reload_mult": 1.1, "role": "escort", "crew": 50},
	"merchant": {"hull": "fluyt", "name": "Merchant Fluyt", "gold": 70, "crates": 3, "cannons": 1,
		"hp_mult": 1.0, "dmg_mult": 0.7, "reload_mult": 1.2, "role": "merchant", "crew": 10, "cargo_rich": true},
	"treasure": {"hull": "treasure", "name": "Treasure Galleon", "gold": 220, "crates": 5, "cannons": 3,
		"hp_mult": 1.0, "dmg_mult": 0.8, "reload_mult": 1.1, "role": "merchant", "crew": 24, "cargo_rich": true},
}

# Named bounty captains, in order. All names are original to this project.
const BOUNTIES := [
	{"captain": "Silas Crane", "ship": "Grey Gannet", "template": "brig", "hp_mult": 1.8, "escorts": ["cutter"], "reward": 450},
	{"captain": "Mad Orla Venn", "ship": "Widow's Wake", "template": "frigate", "hp_mult": 1.5, "escorts": ["cutter", "cutter"], "reward": 700},
	{"captain": "Commodore Ashby", "ship": "Steadfast", "template": "frigate", "hp_mult": 2.0, "escorts": ["brig", "cutter"], "reward": 950},
	{"captain": "The Brothers Rook", "ship": "Twin Gallows", "template": "manowar", "hp_mult": 1.2, "escorts": ["brig", "brig"], "reward": 1300},
	{"captain": "Lady Marisol Ebb", "ship": "Undertow", "template": "manowar", "hp_mult": 1.5, "escorts": ["frigate", "cutter"], "reward": 1700},
	{"captain": "Grand Admiral Varro", "ship": "Leviathan", "template": "manowar", "hp_mult": 2.2, "escorts": ["frigate", "frigate", "brig"], "reward": 2500},
]


static func upgrade_def(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	return {}


static func upgrade_cost(id: String, level: int) -> int:
	var d := upgrade_def(id)
	var raw: float = float(d["base_cost"]) * pow(1.0 + level, 1.35)
	return int(round(raw / 10.0)) * 10


## Build the runtime stat block (pixel units) for a hull + upgrade levels.
static func build_stats(hull_id: String, upgrades: Dictionary) -> Dictionary:
	var h: Dictionary = HULLS[hull_id]
	var lv := func(key: String) -> int: return int(upgrades.get(key, 0))
	var s := {}
	s["hull_id"] = hull_id
	s["name"] = h["name"]
	s["style"] = h["style"]
	s["masts"] = h["masts"]
	s["length"] = float(h["length"]) * U.M
	s["beam"] = float(h["beam"]) * U.M
	s["freeboard"] = float(h["freeboard"]) * U.M
	s["max_hp"] = float(h["hp"]) * (1.0 + 0.15 * lv.call("hull"))
	s["armor"] = minf(0.6, float(h["armor"]) + 0.03 * lv.call("hull"))
	s["max_speed"] = float(h["max_speed"]) * U.M * (1.0 + 0.08 * lv.call("sails"))
	s["linear_drag"] = float(h["linear_drag"])
	s["thrust"] = s["max_speed"] * s["linear_drag"] * 1.03
	s["turn_rate"] = float(h["turn_rate"])
	s["angular_drag"] = float(h["angular_drag"])
	s["keel_grip"] = float(h["keel_grip"])
	s["min_rudder"] = float(h["min_rudder"])
	s["cannons"] = mini(int(h["cannons"]) + lv.call("cannons"), int(h["max_cannons"]))
	s["reload"] = float(h["reload"]) * pow(0.92, lv.call("reload"))
	s["damage"] = float(h["damage"]) * (1.0 + 0.12 * lv.call("gunnery"))
	s["range"] = float(h["range"]) * U.M
	s["muzzle_speed"] = float(h["muzzle_speed"]) * U.M
	s["crew"] = int(round(float(h["crew"]) * (1.0 + 0.2 * lv.call("crew"))))
	s["hold"] = int(h["hold"])
	s["mass"] = float(h["mass"])
	s["threat"] = float(h["threat"])
	s["ram_mult"] = float(h["ram"]) * (1.0 + 0.5 * lv.call("ram"))
	s["ram_resist"] = 0.12 * lv.call("ram")
	s["chasers"] = lv.call("chaser")
	s["chaser_reload"] = 2.2 * pow(0.92, lv.call("reload"))
	s["chaser_damage"] = s["damage"] * 0.8
	s["chaser_range"] = s["range"] * 1.15
	return s


static func build_enemy_stats(template_id: String, notoriety: int, hp_bonus: float = 1.0) -> Dictionary:
	var t: Dictionary = ENEMIES[template_id]
	var s := build_stats(t["hull"], {})
	var n := float(notoriety)
	s["name"] = t["name"]
	s["cannons"] = mini(int(t["cannons"]) + int(notoriety / 3), int(HULLS[t["hull"]]["max_cannons"]))
	s["max_hp"] *= float(t["hp_mult"]) * (1.0 + 0.14 * n) * hp_bonus
	s["damage"] *= float(t["dmg_mult"]) * (1.0 + 0.08 * n)
	s["reload"] *= float(t["reload_mult"]) * maxf(0.75, 1.0 - 0.03 * n)
	s["crew"] = int(round(float(t["crew"]) * (1.0 + 0.12 * n) * hp_bonus))
	s["max_speed"] *= 0.92
	s["thrust"] = s["max_speed"] * s["linear_drag"] * 1.03
	s["chasers"] = 0
	return s
