extends Node3D
## Dev-only: shows characters playing retargeted animations (used for screenshots).
func _ready() -> void:
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0, 1.2, 4.2); cam.look_at(Vector3(0, 0.9, 0))
	var sun := DirectionalLight3D.new(); add_child(sun); sun.rotation_degrees = Vector3(-50, 30, 0); sun.shadow_enabled = true
	var we := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.5, 0.65, 0.85); e.ambient_light_color = Color.WHITE; e.ambient_light_energy = 0.6; we.environment = e; add_child(we)
	var anims := ["ual1/Pistol_Idle", "ual1/Dance", "ual1/Jog_Fwd", "ual2/TreeChopping", "ual1/Crouch_Idle"]
	var chars := ["swat", "adventurer", "woman", "punk", "beach"]
	for i in chars.size():
		var m: Node3D = load("res://assets/chars13/%s.glb" % chars[i]).instantiate()
		add_child(m); m.position = Vector3((i - 2) * 1.6, 0, 0)
		var ap := AnimationPlayer.new(); m.add_child(ap); ap.root_node = NodePath("..")
		for lib in ["ual1", "ual2"]:
			var src: Node = load("res://assets/anim13/%s.glb" % lib).instantiate()
			var sap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
			ap.add_animation_library(lib, sap.get_animation_library(""))
		var an: String = anims[i]
		if not ap.has_animation(an): an = "CharacterArmature|" + anims[i]
		print(chars[i], " ", an, " ", ap.has_animation(an), " ", ap.get_animation_list().slice(0, 4))
		ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		ap.play(an)
