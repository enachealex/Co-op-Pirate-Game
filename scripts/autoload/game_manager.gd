extends Node
## GameManager (spec 3: State, Economy, Wave/Spawn Manager).
## Holds the voyage state machine, the shared treasury, per-player profiles
## (hull, upgrades, cargo, repair kits) and bounty/notoriety progression.
## The SpawnDirector for the running voyage is created as a child of this node.

signal state_changed(new_state: int)
signal treasury_changed(gold: int)
signal message(player_idx: int, text: String, color: Color)   # player_idx -1 = both
signal banner(text: String, sub: String)
signal profile_changed(player_idx: int)
signal victory

enum State { TITLE, LOBBY, PLAYING, PAUSED, VICTORY }

class PlayerProfile:
	var idx := 0
	var hull_id := "sloop"
	var owned_hulls: Array[String] = ["sloop"]
	var upgrades := {"hull": 0, "cannons": 0, "sails": 0, "ram": 0, "gunnery": 0, "reload": 0, "crew": 0, "chaser": 0}
	var repair_kits := 1
	var cargo: Array[int] = []        # value of each cargo crate in the hold
	var sunk := 0
	var captured := 0
	var damage_dealt := 0.0
	var deaths := 0

	func stats() -> Dictionary:
		return ShipDB.build_stats(hull_id, upgrades)

	func cargo_value() -> int:
		var t := 0
		for c in cargo:
			t += c
		return t

var state: int = State.TITLE
var settings := {
	"split_vertical": false,    # false = side-by-side (HSplitContainer), true = stacked (VSplitContainer)
	"master_volume": 0.8,
	"rumble": true,
	"show_arcs": true,
}
var treasury := 0
var profiles: Array[PlayerProfile] = []
var player_count := 2
var notoriety := 0
var bounty_index := 0
var voyage_time := 0.0
var total_sunk := 0
var victory_reached := false

var world: Node = null            # current World (set by Main)
var director: Node = null         # current SpawnDirector


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_state(s: int) -> void:
	state = s
	state_changed.emit(s)


func new_voyage(n_players: int) -> void:
	player_count = clampi(n_players, 1, 2)
	treasury = 250
	notoriety = 0
	bounty_index = 0
	voyage_time = 0.0
	total_sunk = 0
	victory_reached = false
	profiles.clear()
	for i in player_count:
		var p := PlayerProfile.new()
		p.idx = i
		profiles.append(p)
	treasury_changed.emit(treasury)


func end_voyage() -> void:
	if director:
		director.queue_free()
		director = null
	world = null


# --- Economy -------------------------------------------------------------------------

func add_gold(amount: int, player_idx: int = -1, reason: String = "") -> void:
	if amount == 0:
		return
	treasury = maxi(0, treasury + amount)
	treasury_changed.emit(treasury)
	if reason != "":
		var sign_s := "+" if amount > 0 else "-"
		message.emit(player_idx, "%s%s gold  %s" % [sign_s, U.fmt_gold(absi(amount)), reason], Color("ffd34d"))


func can_afford(cost: int) -> bool:
	return treasury >= cost


func spend(cost: int) -> bool:
	if treasury < cost:
		return false
	treasury -= cost
	treasury_changed.emit(treasury)
	return true


func profile(idx: int) -> PlayerProfile:
	return profiles[idx] if idx >= 0 and idx < profiles.size() else null


func notify(player_idx: int, text: String, color: Color = Color.WHITE) -> void:
	message.emit(player_idx, text, color)


# --- Progression ---------------------------------------------------------------------

func register_sink(by_player: int) -> void:
	total_sunk += 1
	if by_player >= 0 and by_player < profiles.size():
		profiles[by_player].sunk += 1
	# Every 6 kills without a bounty also raises notoriety a little.
	if total_sunk % 6 == 0:
		raise_notoriety("Your raids are drawing the Armada's attention.")


func raise_notoriety(reason: String) -> void:
	notoriety += 1
	banner.emit("NOTORIETY %d" % notoriety, reason)


func current_bounty() -> Dictionary:
	if bounty_index < ShipDB.BOUNTIES.size():
		return ShipDB.BOUNTIES[bounty_index]
	# Endless mode after the final captain: recycle the last bounty, scaled up.
	var b: Dictionary = ShipDB.BOUNTIES[ShipDB.BOUNTIES.size() - 1].duplicate()
	var extra := bounty_index - ShipDB.BOUNTIES.size() + 1
	b["captain"] = "Armada Admiral #%d" % extra
	b["ship"] = "Leviathan %s" % ["II", "III", "IV", "V", "VI", "VII"][mini(extra - 1, 5)]
	b["hp_mult"] = float(b["hp_mult"]) + 0.3 * extra
	b["reward"] = int(b["reward"]) + 500 * extra
	return b


func bounty_claimed(_by_player: int, captured: bool) -> void:
	var b := current_bounty()
	var reward := int(b["reward"]) * (2 if captured else 1)
	add_gold(reward, -1, "BOUNTY: %s" % b["captain"])
	banner.emit("BOUNTY CLAIMED", "%s's %s %s" % [b["captain"], b["ship"], "captured!" if captured else "sent to the depths!"])
	bounty_index += 1
	raise_notoriety("The Armada sends a deadlier captain.")
	if bounty_index == ShipDB.BOUNTIES.size() and not victory_reached:
		victory_reached = true
		victory.emit()


func _process(delta: float) -> void:
	if state == State.PLAYING:
		voyage_time += delta
