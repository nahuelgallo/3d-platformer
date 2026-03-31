class_name HookProjectile extends Node3D

# Proyectil del grappling hook. Viaja en linea recta y detecta impacto
# con HookRings (layer 4) y JumpThruPlatforms (layer 3) via raycast frame a frame.

signal hit_target(hit_position: Vector3, collider: Node)
signal missed

var _active := false
var _direction := Vector3.ZERO
var _speed := 0.0
var _max_distance := 0.0
var _origin := Vector3.ZERO
var _visual: MeshInstance3D


func _ready():
	top_level = true
	visible = false
	set_physics_process(false)
	# Visual: esfera pequena naranja
	_visual = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	_visual.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.5, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_visual.material_override = mat
	add_child(_visual)


## Dispara el proyectil desde origin en direction
func fire(origin: Vector3, direction: Vector3, speed: float, max_distance: float) -> void:
	global_position = origin
	_origin = origin
	_direction = direction.normalized()
	_speed = speed
	_max_distance = max_distance
	_active = true
	visible = true
	set_physics_process(true)


func _physics_process(delta: float):
	if not _active:
		return

	var prev_pos = global_position
	global_position += _direction * _speed * delta

	# Raycast entre posicion anterior y actual para detectar impactos
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(prev_pos, global_position)
	# Mask: layer 3 (jump-thru = bit 2) + layer 4 (hook rings = bit 3) + layer 1 (world = bit 0)
	query.collision_mask = 0b1001101  # bits 0, 2, 3, 6 = layers 1, 3, 4, 7
	query.collide_with_areas = true
	query.collide_with_bodies = true
	# Excluir al jugador para que el proyectil no colisione con el
	var player = _get_player()
	if player:
		query.exclude = [player.get_rid()]

	var result = space.intersect_ray(query)
	if result:
		global_position = result.position
		_active = false
		set_physics_process(false)
		hit_target.emit(result.position, result.collider)
		return

	# Si excede distancia maxima, fallo
	if global_position.distance_to(_origin) >= _max_distance:
		_active = false
		set_physics_process(false)
		visible = false
		missed.emit()


## Busca al player subiendo por el arbol hasta encontrar un CharacterBody3D
func _get_player() -> CharacterBody3D:
	var node = get_parent()
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


## Resetea el proyectil
func reset() -> void:
	_active = false
	visible = false
	set_physics_process(false)
	global_position = Vector3.ZERO
