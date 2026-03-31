class_name Checkpoint extends Area3D

## Checkpoint de respawn. Cuando el jugador entra en contacto,
## emite Events.checkpoint_reached con la posicion del checkpoint.
## El player actualiza su spawn_position al recibirla.

@export var respawn_offset := Vector3(0.0, 1.0, 0.0)  # Offset sobre el checkpoint para el respawn

var _activated := false


func _ready():
	# Layer 6 (interactables) = bit 5 = valor 32
	collision_layer = 32
	collision_mask = 2  # Layer 2 (player) = bit 1 = valor 2
	monitorable = false
	monitoring = true

	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _activated:
		return
	if body is CharacterBody3D:
		_activated = true
		Events.checkpoint_reached.emit(global_position + respawn_offset)
