extends Node
## Autoload: shared settings and primitive-building helpers.
var sensitivity := 0.25
var bot_count := 15

func mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c
	if c.a < 1.0: m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func mesh(m: Mesh, c: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = m; mi.material_override = mat(c); mi.position = pos
	return mi

func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new(); b.size = size; return b

func make_character(c: Color) -> Node3D:
	var n := Node3D.new()
	var cap := CapsuleMesh.new(); cap.radius = 0.4; cap.height = 1.8
	n.add_child(mesh(cap, c, Vector3(0, 0.9, 0)))
	var head := SphereMesh.new(); head.radius = 0.3; head.height = 0.6
	n.add_child(mesh(head, Color(1, 0.85, 0.7), Vector3(0, 1.95, 0)))
	n.add_child(mesh(box(Vector3(0.12, 0.12, 0.8)), Color(0.15, 0.15, 0.15), Vector3(0.35, 1.2, -0.4)))
	return n

## Static body with box collider and mesh.
func static_box(size: Vector3, c: Color, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new(); sb.position = pos
	sb.add_child(mesh(box(size), c))
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = size; cs.shape = sh
	sb.add_child(cs); return sb
