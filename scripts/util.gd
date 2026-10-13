extends Node
## Autoload: shared settings and primitive-building helpers.
var sensitivity := 0.25
var bot_count := 15
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

const CHARACTERS := ["res://assets/characters/character-male-a.glb", "res://assets/characters/character-female-b.glb",
	"res://assets/characters/character-male-c.glb", "res://assets/characters/character-female-d.glb"]
const SFX_PATHS := {
	"shoot": "res://assets/audio/shoot.ogg", "reload": "res://assets/audio/reload.ogg",
	"build": "res://assets/audio/build.ogg", "hit": "res://assets/audio/hit.ogg",
	"click": "res://assets/audio/click.ogg", "victory": "res://assets/audio/victory.ogg",
	"eliminated": "res://assets/audio/eliminated.ogg",
	"step0": "res://assets/audio/footstep_grass_000.ogg", "step1": "res://assets/audio/footstep_grass_001.ogg",
	"step2": "res://assets/audio/footstep_grass_002.ogg",
}

## Kenney Mini Character (CC0) holding a Kenney blaster. `_c` kept for API compatibility.
func make_character(_c: Color, idx := -1) -> Node3D:
	var root := Node3D.new(); root.name = "Model"
	var model: Node3D = load(CHARACTERS[idx if idx >= 0 else randi() % CHARACTERS.size()]).instantiate()
	model.scale = Vector3.ONE * 2.7
	model.rotation.y = PI # Kenney models face +Z, our forward is -Z
	root.add_child(model)
	var gun: Node3D = load("res://assets/weapons/blaster-a.glb").instantiate()
	gun.scale = Vector3.ONE * 0.9; gun.position = Vector3(0.35, 1.0, -0.35); gun.rotation.y = PI
	root.add_child(gun)
	play_anim(root, "holding-right")
	return root

func anim_player(model: Node) -> AnimationPlayer:
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	return aps[0] if aps.size() > 0 else null

func play_anim(model: Node, anim: String) -> void:
	var ap := anim_player(model)
	if ap == null or not ap.has_animation(anim): return
	if ap.current_animation != anim:
		var a := ap.get_animation(anim)
		if anim in ["idle", "walk", "sprint", "holding-right", "fall"]: a.loop_mode = Animation.LOOP_LINEAR
		ap.play(anim, 0.15)

var _sfx_cache := {}

## One-shot positional (or UI if pos is null) sound.
func sfx(name: String, pos = null, vol := 0.0) -> void:
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
