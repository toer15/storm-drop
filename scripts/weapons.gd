class_name Weapons
## Weapon definitions and rarity colours. Weapons are plain Dictionaries so they are easy to copy.
const RARITY_COLORS := [Color(0.7, 0.7, 0.7), Color(0.3, 0.85, 0.3), Color(0.25, 0.55, 1.0), Color(0.7, 0.3, 1.0), Color(1.0, 0.75, 0.15)]
const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const TYPES := {
	"pistol":  {"name": "Pistol", "damage": 18.0, "rate": 0.25, "mag": 12, "spread": 0.015, "pellets": 1, "range": 120.0, "sound": "pistol", "reload": "reload_pistol"},
	"ar":      {"name": "Assault Rifle", "damage": 14.0, "rate": 0.12, "mag": 30, "spread": 0.02, "pellets": 1, "range": 200.0, "sound": "heavy", "reload": "reload_rifle"},
	"smg":     {"name": "SMG", "damage": 9.0, "rate": 0.07, "mag": 35, "spread": 0.04, "pellets": 1, "range": 90.0, "sound": "pistol", "reload": "reload_rifle"},
	"shotgun": {"name": "Shotgun", "damage": 9.0, "rate": 0.9, "mag": 5, "spread": 0.09, "pellets": 8, "range": 40.0, "sound": "shotgun", "reload": "pump"},
	"sniper":  {"name": "Sniper", "damage": 85.0, "rate": 1.4, "mag": 1, "spread": 0.0, "pellets": 1, "range": 400.0, "sound": "shotgun", "reload": "reload_rifle"},
	"rocket":  {"name": "Rocket Launcher", "damage": 70.0, "rate": 1.6, "mag": 1, "spread": 0.0, "pellets": 1, "range": 250.0, "sound": "shotgun", "reload": "reload_rifle", "splash": 5.0},
}

static func make(type: String, rarity: int) -> Dictionary:
	var w: Dictionary = TYPES[type].duplicate()
	w.type = type; w.rarity = rarity
	w.damage = w.damage * (1.0 + 0.1 * rarity)
	w.ammo = w.mag
	return w

static func random_drop(rng: RandomNumberGenerator = null) -> Dictionary:
	var r := rng.randf() if rng else randf()
	var rarity := 0 if r < 0.4 else (1 if r < 0.7 else (2 if r < 0.88 else (3 if r < 0.97 else 4)))
	var types := TYPES.keys()
	return make(types[(rng.randi() if rng else randi()) % types.size()], rarity)

static func color(w: Dictionary) -> Color:
	return RARITY_COLORS[w.get("rarity", 0)]

static func label(w: Dictionary) -> String:
	return "%s %s" % [RARITY_NAMES[w.rarity], w.name]
