extends StaticBody3D
## Player-built structure that can be shot down.
var hp := 150.0
func take_damage(amount: float, _killer = null) -> void:
	hp -= amount
	if hp <= 0: queue_free()
func _ready() -> void:
	add_to_group("built")
