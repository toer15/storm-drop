extends StaticBody3D
## Player-built structure that can be shot down. Health lives on the host (see game.piece_hit).
var hp := 150.0
func take_damage(amount: float, _killer = null) -> void:
	var g = get_tree().current_scene
	if g and g.has_method("piece_hit"): g.piece_hit(self, amount)
	else:
		hp -= amount
		if hp <= 0: queue_free()
func _ready() -> void:
	add_to_group("built")
