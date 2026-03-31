class_name FlexPole extends Node3D

## Palo flexible / arbol catapulta. El jugador se engancha con el hook,
## dobla el palo con input (S), orbita alrededor (A/D), y al saltar
## el palo lo catapulta en la direccion opuesta.
## Inspirado en la mecanica de Crimson Desert.

signal pole_launched(launch_velocity: Vector3)
signal pole_grabbed(by: CharacterBody3D)
signal pole_released()

enum PoleState { IDLE, BENDING, RELEASE, SPRINGING_BACK }

@export var max_bend_angle: float = 45.0       # Grados maximos de doblez
@export var bend_speed: float = 2.0            # Velocidad de doblez (bend_amount/sec)
@export var launch_force_min: float = 45.0     # Fuerza con doblez minimo
@export var launch_force_max: float = 105.0    # Fuerza con doblez maximo
@export var spring_back_speed: float = 8.0     # Velocidad de retorno a posicion original
@export var pole_height: float = 6.0           # Altura del palo

var _state := PoleState.IDLE
var bend_amount: float = 0.0  # 0.0 a 1.0 — cuanto esta doblado
var hook_height_ratio: float = 1.0  # 0.0=base, 1.0=punta — donde se engancho el hook

var _pole_bend: Node3D       # Pivot de rotacion
var _pole_mesh: MeshInstance3D
var _pole_base: MeshInstance3D
var _hook_point: Area3D
var _bend_direction := Vector3.FORWARD  # Direccion en la que se dobla (hacia el jugador)


func _ready():
	_setup_visuals()
	_setup_hook_point()


func _setup_visuals():
	# Base fija del palo
	_pole_base = MeshInstance3D.new()
	_pole_base.name = "PoleBase"
	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = 0.2
	base_mesh.bottom_radius = 0.3
	base_mesh.height = 0.5
	_pole_base.mesh = base_mesh
	var base_mat = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.35, 0.22, 0.1)  # Marron oscuro
	_pole_base.material_override = base_mat
	_pole_base.position = Vector3(0, 0.25, 0)
	add_child(_pole_base)

	# Pivot de rotacion para el doblez
	_pole_bend = Node3D.new()
	_pole_bend.name = "PoleBend"
	_pole_bend.position = Vector3(0, 0.5, 0)  # Base del palo
	add_child(_pole_bend)

	# Palo visual (hijo del pivot)
	_pole_mesh = MeshInstance3D.new()
	_pole_mesh.name = "PoleMesh"
	var pole_mesh_res = CylinderMesh.new()
	pole_mesh_res.top_radius = 0.08
	pole_mesh_res.bottom_radius = 0.15
	pole_mesh_res.height = pole_height
	_pole_mesh.mesh = pole_mesh_res
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.45, 0.3, 0.12)  # Marron claro
	_pole_mesh.material_override = pole_mat
	# Centrar el mesh para que la base quede en el pivot
	_pole_mesh.position = Vector3(0, pole_height * 0.5, 0)
	_pole_bend.add_child(_pole_mesh)


func _setup_hook_point():
	_hook_point = Area3D.new()
	_hook_point.name = "HookPoint"
	# Layer 7 (flex_poles) = bit 6 = valor 64
	_hook_point.collision_layer = 64
	_hook_point.collision_mask = 0
	_hook_point.monitorable = true
	_hook_point.monitoring = false

	var shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.8  # Area de enganche generosa
	shape.shape = sphere
	_hook_point.add_child(shape)
	# Posicionar en la punta del palo
	_hook_point.position = Vector3(0, 0.5 + pole_height * 0.85, 0)
	add_child(_hook_point)


## Posicion global del punto de enganche (para el crosshair)
func get_hook_point_position() -> Vector3:
	if _hook_point:
		return _hook_point.global_position
	return global_position + Vector3.UP * pole_height


## Llamado por FlexPoleState cuando el jugador se engancha
## hit_y es la altura del punto de impacto del hook
func grab(player_node: CharacterBody3D, hit_y: float = -1.0) -> void:
	_state = PoleState.BENDING
	bend_amount = 0.0
	# Calcular donde en el palo se engancho (0=base, 1=punta)
	if hit_y >= 0.0:
		var base_y = global_position.y
		var top_y = base_y + pole_height
		hook_height_ratio = clampf((hit_y - base_y) / pole_height, 0.1, 1.0)
	else:
		hook_height_ratio = 1.0  # Default: punta
	pole_grabbed.emit(player_node)
	print("FlexPole: enganche a altura %.0f%% del palo (mult: %.1fx)" % [hook_height_ratio * 100, _get_height_multiplier()])


## Llamado por FlexPoleState para actualizar el doblez (cada frame)
func update_bend(amount: float, player_direction: Vector3) -> void:
	bend_amount = clampf(amount, 0.0, 1.0)
	_bend_direction = player_direction.normalized()
	_apply_visual_bend()


## Multiplicador de fuerza por altura de enganche
## Punta (1.0) = x2.0, medio (0.5) = x1.0, base (0.1) = x0.5
func _get_height_multiplier() -> float:
	return lerpf(0.5, 2.0, hook_height_ratio)


## Calcula y retorna la velocidad de lanzamiento
## Mas bend = mas vertical. Mas alto el enganche = mas fuerza.
func calculate_launch_velocity(player_position: Vector3) -> Vector3:
	var pole_pos = global_position
	# Direccion horizontal: opuesta a donde esta el jugador respecto al palo
	var launch_dir = (pole_pos - player_position)
	launch_dir.y = 0.0
	launch_dir = launch_dir.normalized()

	# Componente vertical escala con bend: mas doblado = mas vertical
	var vertical_ratio = lerpf(0.4, 0.9, bend_amount)
	launch_dir.y = vertical_ratio
	launch_dir = launch_dir.normalized()

	var force = lerpf(launch_force_min, launch_force_max, bend_amount)
	# Multiplicar por altura de enganche (punta = x2, base = x0.5)
	force *= _get_height_multiplier()
	return launch_dir * force


## Llamado cuando el jugador salta/suelta — inicia el lanzamiento
func release() -> void:
	_state = PoleState.SPRINGING_BACK
	pole_released.emit()


func _physics_process(delta: float):
	match _state:
		PoleState.SPRINGING_BACK:
			bend_amount = move_toward(bend_amount, 0.0, spring_back_speed * delta)
			_apply_visual_bend()
			if bend_amount <= 0.01:
				bend_amount = 0.0
				_state = PoleState.IDLE
				_pole_bend.rotation = Vector3.ZERO


func _apply_visual_bend():
	if not _pole_bend:
		return
	# Rotar el pivot en la direccion del doblez
	var bend_angle_rad = deg_to_rad(max_bend_angle * bend_amount)
	# Calcular el eje de rotacion perpendicular a la direccion del doblez
	var bend_2d = Vector2(_bend_direction.x, _bend_direction.z).normalized()
	# El palo se dobla HACIA el jugador, asi que rotamos en el eje perpendicular
	_pole_bend.rotation = Vector3(
		bend_2d.y * bend_angle_rad,   # Rotation X = componente Z de la direccion
		0.0,
		-bend_2d.x * bend_angle_rad   # Rotation Z = componente X negado
	)
