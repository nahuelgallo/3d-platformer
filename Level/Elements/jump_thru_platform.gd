class_name JumpThruPlatform extends AnimatableBody3D

## Plataforma con colision solo desde arriba (one-way collision manual en 3D).
## Si el jugador esta por debajo de la superficie, desactiva colision para que pase.
## Crouch + move_down = drop through (desactiva colision temporalmente).
## Cambiar "size" en el inspector actualiza collision y mesh juntos.

@export var size := Vector3(4.0, 0.2, 2.0):
	set(value):
		size = value
		_update_size()

@export var drop_through_duration := 0.3

var _collision_shape: CollisionShape3D
var _mesh: MeshInstance3D
var _player: CharacterBody3D
var _is_dropping := false  # True durante drop-through, ignora la logica normal


func _ready():
	# Buscar hijos existentes (busca recursivo por si el mesh esta dentro del collision)
	_collision_shape = _find_child_of_type(self, CollisionShape3D)
	_mesh = _find_child_of_type(self, MeshInstance3D)

	# Crear solo si no existen
	if not _collision_shape:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape3D"
		_collision_shape.shape = BoxShape3D.new()
		add_child(_collision_shape)

	if not _mesh:
		_mesh = MeshInstance3D.new()
		_mesh.name = "MeshInstance3D"
		_mesh.mesh = BoxMesh.new()
		add_child(_mesh)

	# Asegurar que tengan BoxShape3D y BoxMesh
	if not _collision_shape.shape is BoxShape3D:
		_collision_shape.shape = BoxShape3D.new()
	if not _mesh.mesh is BoxMesh:
		_mesh.mesh = BoxMesh.new()

	_update_size()

	# Collision layer 3 (one_way_platforms) = bit 2 = valor 4
	collision_layer = 4
	collision_mask = 0


func _physics_process(_delta: float):
	if _is_dropping:
		return

	# Buscar al player una sola vez
	if not _player:
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		if not _player:
			return

	# Fondo de la plataforma = posicion global Y - mitad del alto
	var bottom_y := global_position.y - size.y * 0.5
	var player_feet_y := _player.global_position.y

	# Solo desactivar colision si los pies estan por debajo del fondo de la plataforma.
	# Esto evita flickering al caminar entre plataformas normales y jump-thru al mismo nivel.
	if player_feet_y < bottom_y:
		_collision_shape.disabled = true
	else:
		_collision_shape.disabled = false


func _update_size():
	if _collision_shape and _collision_shape.shape is BoxShape3D:
		_collision_shape.shape.size = size
	if _mesh and _mesh.mesh is BoxMesh:
		_mesh.mesh.size = size


## Busca el primer hijo del tipo dado, recursivamente.
func _find_child_of_type(node: Node, type) -> Node:
	for child in node.get_children():
		if is_instance_of(child, type):
			return child
		var found = _find_child_of_type(child, type)
		if found:
			return found
	return null


## Desactiva la colision temporalmente para que el jugador caiga a traves.
func drop_through() -> void:
	if not _collision_shape:
		return
	_is_dropping = true
	_collision_shape.disabled = true
	await get_tree().create_timer(drop_through_duration).timeout
	_collision_shape.disabled = false
	_is_dropping = false
