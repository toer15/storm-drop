extends Node
## Autoload: shared settings and primitive-building helpers.
var sensitivity := 0.25
var bot_count := 49   # 50-player matches (phones default to fewer, see _ready)
var difficulty := 1   # 0 Easy, 1 Normal, 2 Hard
var debug_ai := false  # F3 or Settings: show each bot's current decision
## Screenshot mode: `godot -- --shot=res_or_user_path.png [--tab=Locker] [--delay=4]` saves the screen then quits.
var shot_path := ""
var shot_tab := ""
var shot_delay := 4.0
var hold_boot := false

func _ready() -> void:
	if OS.has_feature("mobile") or OS.has_feature("web"): bot_count = 29
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot_path = a.substr(7)
		elif a.begins_with("--tab="): shot_tab = a.substr(6)
		elif a.begins_with("--delay="): shot_delay = float(a.substr(8))
		elif a == "--hold-boot": hold_boot = true
		elif a == "--touch": touch_enabled = true
		elif a == "--debug-ai": debug_ai = true
		elif a.begins_with("--difficulty="): difficulty = int(a.substr(13))
		elif a.begins_with("--bots="): bot_count = int(a.substr(7))
	if shot_path != "":
		await get_tree().create_timer(shot_delay).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		get_tree().quit()
## Touch controls: shown automatically on touch devices, can be toggled in Settings.
var touch_enabled := DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") \
	or OS.has_feature("web_android") or OS.has_feature("web_ios")
var touch_move := Vector2.ZERO   # virtual joystick, -1..1
var touch_look := Vector2.ZERO   # accumulated look delta (pixels), consumed by player
var touch_fire := false
var touch_sprint := false
var touch_jump := false

func mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c
	if c.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func mesh(m: Mesh, c: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = m; mi.material_override = mat(c); mi.position = pos
	return mi

func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new(); b.size = size; return b

const CHAR_DIR := "res://assets/chars13/%s.glb"
var CHARACTERS: Array = ["swat", "adventurer", "hooded", "astronaut", "farmer", "punk", "beach", "casual", "woman", "woman2", "worker"].map(func(x): return CHAR_DIR % x)
const SFX_PATHS := {
	"shoot": "res://assets/audio/shoot.ogg", "reload": "res://assets/audio/reload.ogg",
	"build": "res://assets/audio/build.ogg", "hit": "res://assets/audio/hit.ogg",
	"click": "res://assets/audio/click.ogg", "victory": "res://assets/audio/victory.ogg",
	"eliminated": "res://assets/audio/eliminated.ogg",
	"step0": "res://assets/audio/footstep_grass_000.ogg", "step1": "res://assets/audio/footstep_grass_001.ogg",
	"step2": "res://assets/audio/footstep_grass_002.ogg", "coin": "res://assets/audio/click.ogg",
	"pistol": "res://assets/sfx13/pistol.wav", "heavy": "res://assets/sfx13/heavy.wav", "shotgun": "res://assets/sfx13/shotgun.wav",
	"reload_rifle": "res://assets/sfx13/reload_rifle.wav", "reload_pistol": "res://assets/sfx13/reload_pistol.wav", "pump": "res://assets/sfx13/pump.wav",
}

## Game animation names -> clips from the Quaternius Universal Animation Library 1+2 (CC0), retargeted at import
## onto every character through Godot's humanoid SkeletonProfile (see tools/import/ and tools/fix_rig.py).
const ANIMS := {
	"idle": "ual1/Idle", "holding-right": "ual1/Pistol_Aim_Neutral", "walk": "ual1/Jog_Fwd", "sprint": "ual1/Sprint",
	"walk-gun": "ual1/Walk", "jump": "ual1/Jump_Start", "fall": "ual1/Jump", "land": "ual1/Jump_Land",
	"crouch": "ual1/Crouch_Idle", "crouch-walk": "ual1/Crouch_Fwd", "die": "ual1/Death01", "hit": "ual1/Hit_Chest",
	"sit": "ual1/Sitting_Idle", "drive": "ual2/NinjaJump_Idle", "glide": "ual2/NinjaJump_Idle", "skydive": "ual1/Swim_Idle",
	"holding-right-shoot": "ual1/Pistol_Shoot", "reload": "ual1/Pistol_Reload", "attack-melee-right": "ual2/Sword_Regular_A",
	"pickaxe": "ual2/TreeChopping", "interact-right": "ual1/Interact", "build": "ual1/Interact", "pick-up": "ual2/Consume",
	"open-chest": "ual2/Chest_Open", "roll": "ual1/Roll",
	# emotes
	"emote-yes": "ual2/Yes", "emote-no": "ual2/Idle_No", "emote-wave": "ual2/Idle_Rail_Call", "emote-dance": "ual1/Dance",
	"emote-zombie": "ual2/Zombie_Walk_Fwd", "emote-spell": "ual1/Spell_Simple_Idle", "emote-fold": "ual2/Idle_FoldArms",
	"emote-phone": "ual2/Idle_TalkingPhone", "emote-box": "ual1/Punch_Jab", "emote-swim": "ual1/Swim_Fwd",
	"emote-harvest": "ual2/Farm_Harvest", "emote-fix": "ual1/Fixing_Kneeling", "emote-slide": "ual2/Slide",
	"attack-kick-right": "ual1/Punch_Cross",
}
const LOOPING := ["idle", "holding-right", "holding-right-shoot", "walk", "sprint", "walk-gun", "fall", "crouch", "crouch-walk", "sit", "drive", "glide",
	"skydive", "pickaxe", "emote-dance", "emote-zombie", "emote-spell", "emote-fold", "emote-phone", "emote-swim", "emote-no", "emote-slide"]
var _libs := {}
var _EMOTE_CLIPS: Array = ANIMS.keys().filter(func(k): return k.begins_with("emote") or k in ["sit", "pick-up", "open-chest"]).map(func(k): return ANIMS[k])

func _anim_libs() -> Dictionary:
	if _libs.is_empty():
		for l in ["ual1", "ual2"]:
			var src: Node = load("res://assets/anim13/%s.glb" % l).instantiate()
			var ap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
			var lib: AnimationLibrary = ap.get_animation_library("")
			for n in LOOPING:
				var clip: String = ANIMS[n]
				if clip.begins_with(l + "/") and lib.has_animation(clip.substr(5)): lib.get_animation(clip.substr(5)).loop_mode = Animation.LOOP_LINEAR
			_libs[l] = lib; src.free()
	return _libs


## Quaternius character (CC0) with cosmetics, a shared humanoid animation set, a right-hand weapon mount and a
## back bling on the chest bone. skin/backbling/pickaxe are Profile catalog ids ("" = random skin).
func make_character(skin := "", backbling := "bb_none", pickaxe := "pick_default") -> Node3D:
	var root := Node3D.new(); root.name = "Model"
	var path: String
	if skin == "": path = CHARACTERS[randi() % CHARACTERS.size()]
	elif skin.begins_with("res://"): path = skin
	else: path = Profile.CATALOG[skin].data.model
	root.set_meta("path", path)
	var model: Node3D = load(path).instantiate(); model.name = "Body"
	model.rotation.y = PI # Quaternius models face +Z, our forward is -Z
	stylize(model, 0.0 if low_end() else 0.006, 0.3)
	root.add_child(model)
	var ap := AnimationPlayer.new(); ap.name = "Anim"; model.add_child(ap); ap.root_node = NodePath("..")
	for l in _anim_libs(): ap.add_animation_library(l, _libs[l])
	root.set_meta("ap", ap)
	var skel: Skeleton3D = model.find_child("GeneralSkeleton", true, false)
	root.set_meta("skeleton", skel)
	var hand := BoneAttachment3D.new(); hand.name = "Hand"; skel.add_child(hand); hand.bone_name = "RightHand"
	var mount := Node3D.new(); mount.name = "Mount"; hand.add_child(mount); mount.top_level = true
	root.set_meta("mount", mount); root.set_meta("hand", hand)
	var pick := Gear.make_pickaxe(pickaxe); pick.visible = false; mount.add_child(pick)
	root.set_meta("pickaxe", pick)
	var chest := BoneAttachment3D.new(); chest.name = "Back"; skel.add_child(chest); chest.bone_name = "UpperChest"
	var bb := Gear.make_backbling(backbling)
	if bb:
		var holder := Node3D.new(); chest.add_child(holder); holder.add_child(bb); root.set_meta("backbling", holder)
	root.set_meta("gun_type", "")
	play_anim(root, "idle")
	return root

## Keep the held item aligned with the body (the hand bone supplies the position, this the orientation).
func align_gear(root: Node3D, aim_pitch := 0.0) -> void:
	if not root.has_meta("mount"): return
	var mount: Node3D = root.get_meta("mount")
	var pick: Node3D = root.get_meta("pickaxe")
	var b := root.global_basis.orthonormalized()
	var hand: Node3D = root.get_meta("hand")
	var ap := anim_player(root)
	mount.visible = not (ap and (String(ap.current_animation) in _EMOTE_CLIPS))
	var hb: Basis = b * (Basis.from_euler(Vector3(-0.4, 0, -0.25)) if pick.visible else Basis(Vector3.RIGHT, aim_pitch))
	var sc := root.global_basis.get_scale().x
	mount.global_transform = Transform3D(hb.scaled(Vector3.ONE * sc), hand.global_position + b * Vector3(-0.02, 0.0, -0.03) * sc)
	if root.has_meta("backbling"):
		var bb: Node3D = root.get_meta("backbling")
		bb.global_basis = b.scaled(Vector3.ONE * root.global_basis.get_scale().x)
		bb.global_position = bb.get_parent().global_position + b * Vector3(0, 0.05, 0.22) * root.global_basis.get_scale().x

## True on phones / web / the Compatibility renderer: use cheaper effects there.
func low_end() -> bool:
	return RenderingServer.get_rendering_device() == null or OS.has_feature("mobile") or OS.has_feature("web")

var _outline_cache := {}
## Toon look: rim light + inverted-hull outline (next_pass) on every surface of a model.
func stylize(node: Node, thickness := 0.012, rim := 0.35) -> void:
	if not _outline_cache.has(thickness):
		var om := ShaderMaterial.new(); om.shader = preload("res://shaders/outline.gdshader")
		om.set_shader_parameter("thickness", thickness); _outline_cache[thickness] = om
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null: continue
		for i in mi.mesh.get_surface_count():
			var m = mi.get_active_material(i)
			if not (m is StandardMaterial3D): continue
			var d: StandardMaterial3D = m.duplicate()
			d.rim_enabled = true; d.rim = rim; d.rim_tint = 0.3
			if thickness > 0.0: d.next_pass = _outline_cache[thickness]
			mi.set_surface_override_material(i, d)

## Show the pickaxe or the gun model for `type` (with a faint rarity-colour sheen).
func hold(model: Node3D, pickaxe: bool, tint := Color.WHITE, type := "ar") -> void:
	if not model.has_meta("mount"): return
	var mount: Node3D = model.get_meta("mount"); var pick: Node3D = model.get_meta("pickaxe")
	pick.visible = pickaxe
	var old: Node3D = mount.get_node_or_null("Gun")
	if pickaxe:
		if old: old.visible = false
		return
	if old == null or model.get_meta("gun_type") != type:
		if old: old.free()
		old = Gear.make_gun(type); mount.add_child(old); model.set_meta("gun_type", type)
		old.position = Vector3(0, 0.02, -0.06)
	old.visible = true

## Muzzle flash (Kenney Particle Pack sprite + short light) at a gun's "Muzzle" marker.
var _flash_tex: Texture2D
func muzzle_flash(gun: Node3D, big := false) -> void:
	if gun == null or not gun.is_inside_tree(): return
	var mz: Node3D = gun.get_node_or_null("Muzzle")
	if mz == null: return
	if _flash_tex == null: _flash_tex = load("res://assets/fx13/muzzle_front.png")
	var s := Sprite3D.new(); s.texture = _flash_tex; s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.pixel_size = (0.0016 if big else 0.0009) * randf_range(0.8, 1.2); s.modulate = Color(1, 0.85, 0.5)
	s.shaded = false; s.no_depth_test = false; s.rotation.z = randf() * TAU
	mz.add_child(s)
	if not low_end():
		var l := OmniLight3D.new(); l.light_color = Color(1, 0.75, 0.4); l.light_energy = 2.5; l.omni_range = 4.0; mz.add_child(l)
		get_tree().create_timer(0.05).timeout.connect(l.queue_free)
	get_tree().create_timer(0.05).timeout.connect(s.queue_free)

func anim_player(model: Node) -> AnimationPlayer:
	if model.has_meta("ap"): return model.get_meta("ap")
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	return aps[0] if aps.size() > 0 else null

func play_anim(model: Node, anim: String, speed := 1.0) -> void:
	var ap := anim_player(model)
	if ap == null: return
	var clip: String = ANIMS.get(anim, anim)
	if not ap.has_animation(clip): return
	if ap.current_animation != clip: ap.play(clip, 0.18, speed)

var _sfx_cache := {}
var _music: AudioStreamPlayer
var music_volume := -12.0
## Looping background music (CC0 tracks from OpenGameArt, see CREDITS.md); keeps playing across scene changes.
func music(path: String) -> void:
	if _music == null:
		_music = AudioStreamPlayer.new(); _music.bus = "Master"; add_child(_music)
	if _music.has_meta("path") and _music.get_meta("path") == path and _music.playing: return
	var st = load(path)
	if st == null: return
	st = st.duplicate(); if st is AudioStreamOggVorbis: st.loop = true
	_music.stream = st; _music.volume_db = music_volume; _music.set_meta("path", path); _music.play()

## One-shot positional (or UI if pos is null) sound.
func sfx(name: String, pos = null, vol := 0.0) -> void:
	if Net.dedicated: return
	var tree := get_tree()
	if tree == null or tree.current_scene == null: return
	var p: Node
	if pos == null:
		p = AudioStreamPlayer.new()
	else:
		p = AudioStreamPlayer3D.new(); p.unit_size = 12.0
	if not _sfx_cache.has(name): _sfx_cache[name] = load(SFX_PATHS[name])
	p.stream = _sfx_cache[name]; p.volume_db = vol
	tree.current_scene.add_child(p)
	if pos != null: p.global_position = pos
	p.play(); p.finished.connect(p.queue_free)

## Instance a model with trimesh collision attached.
func static_model(path: String, scale_f: float, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new(); sb.position = pos
	var m: Node3D = load(path).instantiate(); m.scale = Vector3.ONE * scale_f; sb.add_child(m)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var cs := CollisionShape3D.new(); cs.shape = mi.mesh.create_trimesh_shape()
		var t: Transform3D = mi.transform; var n: Node = mi.get_parent()
		while n != m: t = n.transform * t; n = n.get_parent()
		cs.transform = m.transform * t
		sb.add_child(cs)
	return sb

## Static body with box collider and mesh.
func static_box(size: Vector3, c: Color, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new(); sb.position = pos
	sb.add_child(mesh(box(size), c))
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = size; cs.shape = sh
	sb.add_child(cs); return sb
