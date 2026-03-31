class_name HookRing extends Node3D

## Aro de gancho (punto de enganche para grappling hook).
## Solo visual por ahora. Area3D en layer 4 (hook_points) para que
## el grappling hook la detecte en Fase 7.
## monitorable=true para que otros la detecten, monitoring=false porque ella no detecta nada.

@onready var _area: Area3D = $Area3D


func _ready():
	if _area:
		# Layer 4 (hook_points) = bit 3 = valor 8
		_area.collision_layer = 8
		_area.collision_mask = 0
		_area.monitorable = true
		_area.monitoring = false
