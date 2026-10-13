extends Node
## Autoload "Profile": soft currency (Drop Coins), cosmetics, battle pass XP and career stats,
## saved to user://profile.cfg with ConfigFile. No real money anywhere.
const SAVE := "user://profile.cfg"
const XP_PER_TIER := 600
const TIERS := 20
const RARITY_PRICE := [500, 800, 1200, 1500, 2000]

## Cosmetic catalog. type: skin / backbling / pickaxe / emote. rarity 0-4. bp = battle-pass only.
var CATALOG := {}
var coins := 1000
var xp := 0
var owned := {}
var equipped := {"skin": "skin_scout", "backbling": "bb_none", "pickaxe": "pick_default", "emote": "emote_nod"}
var stats := {"matches": 0, "wins": 0, "kills": 0, "top10": 0, "deaths": 0, "best_place": 99, "play_time": 0.0}
var mode := "Solo"
var last_result := {}

func _init() -> void:
	var skins := [["scout", "adventurer"], ["ranger", "woman"], ["blaze", "punk"], ["nova", "woman2"],
		["tank", "swat"], ["vex", "hooded"], ["drift", "casual"], ["luma", "beach"],
		["rook", "worker"], ["sable", "farmer"], ["kite", "astronaut"], ["zephyr", "swat"]]
	for i in skins.size():
		var s: Array = skins[i]
		_add("skin_" + s[0], "skin", s[0].capitalize(), mini(i / 2, 4), {"model": "res://assets/chars13/%s.glb" % s[1]}, i >= 10)
	_add("bb_none", "backbling", "No Back Bling", 0, {"shape": "none"})
	_add("bb_cube", "backbling", "Cube Pack", 1, {"shape": "box", "color": Color(0.2, 0.7, 1)})
	_add("bb_orb", "backbling", "Storm Orb", 3, {"shape": "sphere", "color": Color(0.7, 0.3, 1)})
	_add("bb_tank", "backbling", "Jet Tank", 2, {"shape": "cylinder", "color": Color(1, 0.4, 0.1)})
	_add("bb_crystal", "backbling", "Gold Crystal", 4, {"shape": "prism", "color": Color(1, 0.8, 0.2)}, true)
	_add("bb_candy", "backbling", "Candy Pack", 1, {"shape": "box", "color": Color(1, 0.4, 0.7)})
	_add("pick_default", "pickaxe", "Trusty Axe", 0, {"color": Color(0.6, 0.6, 0.65)})
	_add("pick_neon", "pickaxe", "Neon Pick", 2, {"color": Color(0.1, 1, 0.9)})
	_add("pick_gold", "pickaxe", "Gold Smasher", 4, {"color": Color(1, 0.8, 0.1)})
	_add("pick_candy", "pickaxe", "Candy Hammer", 1, {"color": Color(1, 0.3, 0.6)})
	_add("pick_void", "pickaxe", "Void Cleaver", 3, {"color": Color(0.4, 0.1, 0.8)}, true)
	_add("emote_nod", "emote", "Nod", 0, {"anim": "emote-yes"})
	_add("emote_nope", "emote", "Nope", 1, {"anim": "emote-no"})
	_add("emote_wave", "emote", "Wave", 1, {"anim": "emote-wave"})
	_add("emote_scoop", "emote", "Scoop", 2, {"anim": "pick-up"})
	_add("emote_kick", "emote", "Shadow Box", 3, {"anim": "emote-box"})
	_add("emote_chill", "emote", "Chill", 2, {"anim": "sit"}, true)
	_add("emote_dance", "emote", "Groove", 2, {"anim": "emote-dance"})
	_add("emote_zombie", "emote", "Zombie Shuffle", 3, {"anim": "emote-zombie"})
	_add("emote_spell", "emote", "Hocus Pocus", 2, {"anim": "emote-spell"})
	_add("emote_swim", "emote", "Dry Swim", 3, {"anim": "emote-swim"})
	_add("emote_slide", "emote", "Floor Slide", 4, {"anim": "emote-slide"}, true)
	_add("emote_fold", "emote", "Unbothered", 1, {"anim": "emote-fold"})
	_add("emote_phone", "emote", "On The Phone", 1, {"anim": "emote-phone"})
	for id in ["skin_scout", "bb_none", "pick_default", "emote_nod", "emote_dance"]: owned[id] = true
	load_profile()

func _add(id: String, type: String, nm: String, rarity: int, data: Dictionary, bp := false) -> void:
	CATALOG[id] = {"id": id, "type": type, "name": nm, "rarity": rarity, "data": data, "bp": bp, "price": RARITY_PRICE[rarity]}

## Battle pass: tier -> reward. {"coins": n} or {"item": id}
func bp_reward(tier: int) -> Dictionary:
	var items := {3: "bb_crystal", 6: "pick_void", 9: "emote_chill", 12: "skin_kite", 14: "emote_slide", 16: "bb_orb", 20: "skin_zephyr"}
	if items.has(tier): return {"item": items[tier]}
	return {"coins": 100 if tier % 2 == 1 else 200}

func tier() -> int:
	return mini(xp / XP_PER_TIER, TIERS)

## Today's shop: 6 non-battle-pass items, rotated daily by the date.
func daily_shop() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system() / 86400.0)
	var pool: Array = CATALOG.values().filter(func(it): return not it.bp and it.price > 0 and it.rarity > 0 or it.type == "skin" and not it.bp and it.id != "skin_scout")
	var picks := []
	while picks.size() < 6 and pool.size() > 0:
		picks.append(pool.pop_at(rng.randi() % pool.size()))
	return picks

func seconds_to_reset() -> int:
	return 86400 - int(Time.get_unix_time_from_system()) % 86400

func buy(id: String) -> bool:
	var it: Dictionary = CATALOG[id]
	if owned.has(id) or coins < it.price: return false
	coins -= it.price; owned[id] = true; save_profile(); return true

func equip(id: String) -> void:
	if owned.has(id): equipped[CATALOG[id].type] = id; save_profile()

func item(slot: String) -> Dictionary:
	return CATALOG.get(equipped[slot], {})

## Called at end of a match. Returns rewards for the results screen.
func award_match(kills: int, place: int, won: bool, seconds: float) -> Dictionary:
	var gained_xp := 150 + kills * 60 + maxi(0, 20 - place) * 15 + (400 if won else 0)
	var gained_coins := 25 + kills * 15 + (150 if won else 0)
	var old_tier := tier()
	xp += gained_xp; coins += gained_coins
	var unlocked := []
	for t in range(old_tier + 1, tier() + 1):
		var r := bp_reward(t)
		if r.has("item"): owned[r.item] = true; unlocked.append(CATALOG[r.item].name)
		else: coins += r.coins; unlocked.append("%d Drop Coins" % r.coins)
	stats.matches += 1; stats.kills += kills; stats.play_time += seconds
	if won: stats.wins += 1
	else: stats.deaths += 1
	if place <= 10: stats.top10 += 1
	stats.best_place = mini(stats.best_place, place)
	save_profile()
	last_result = {"xp": gained_xp, "coins": gained_coins, "unlocked": unlocked, "tier": tier()}
	return last_result

func save_profile() -> void:
	var cf := ConfigFile.new()
	cf.set_value("p", "coins", coins); cf.set_value("p", "xp", xp)
	cf.set_value("p", "owned", owned.keys()); cf.set_value("p", "equipped", equipped)
	cf.set_value("p", "stats", stats)
	cf.save(SAVE)

func load_profile() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK: return
	coins = cf.get_value("p", "coins", coins); xp = cf.get_value("p", "xp", xp)
	for id in cf.get_value("p", "owned", []): if CATALOG.has(id): owned[id] = true
	var eq: Dictionary = cf.get_value("p", "equipped", {})
	for k in eq: if owned.has(eq[k]): equipped[k] = eq[k]
	var st: Dictionary = cf.get_value("p", "stats", {})
	for k in st: stats[k] = st[k]
