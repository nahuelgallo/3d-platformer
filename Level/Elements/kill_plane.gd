class_name KillPlane extends Area3D

## Plano de muerte. Cualquier cuerpo que entre emite Events.kill_plane_touched.
## Colocar debajo del nivel como red de seguridad.

func _ready():
	# Layer 5 (kill_zones) = bit 4 = valor 16
	collision_layer = 16
	collision_mask = 2  # Layer 2 (player)
	monitorable = false
	monitoring = true

	body_entered.connect(_on_body_entered)


func _on_body_entered(_body: PhysicsBody3D) -> void:
	Events.kill_plane_touched.emit()
