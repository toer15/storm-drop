extends Node3D
func _ready() -> void:
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(1.5, 3.0, 3.2); cam.look_at(Vector3(0, 0, -0.8))
	var sun := DirectionalLight3D.new(); add_child(sun); sun.rotation_degrees = Vector3(-50, 30, 0)
	var we := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.5, 0.65, 0.85); e.ambient_light_color = Color.WHITE; e.ambient_light_energy = 0.7; we.environment = e; add_child(we)
	var i := 0
	for t in Gear.GUNS:
		var g := Gear.make_gun(t); add_child(g); g.position = Vector3(-2.5 + i * 1.0, 0, 0)
		var s := Util.mesh(SphereMesh.new(), Color.RED); s.scale = Vector3.ONE * 0.06; g.get_node("Muzzle").add_child(s)
		var o := Util.mesh(SphereMesh.new(), Color.GREEN); o.scale = Vector3.ONE * 0.06; g.add_child(o)
		i += 1
	i = 0
	for p in Gear.PICKAXES:
		var k := Gear.make_pickaxe(p); add_child(k); k.position = Vector3(-2.5 + i * 1.0, 0, -2.0); i += 1
		var o := Util.mesh(SphereMesh.new(), Color.GREEN); o.scale = Vector3.ONE * 0.06; k.add_child(o)
