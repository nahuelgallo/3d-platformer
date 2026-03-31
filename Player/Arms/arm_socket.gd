class_name ArmSocket extends Node3D

# Socket que gestiona el brazo activo.
# Delega inputs al brazo equipado sin saber que brazo es.
# Soporta multiples brazos como hijos: switch_arm() rota entre ellos.

var current_arm: Node3D
var _arms: Array[Node3D] = []
var _current_index := 0
var _player: CharacterBody3D


func _ready():
	_player = get_parent()
	# Registrar todos los hijos como brazos disponibles
	for child in get_children():
		if child.has_method("_setup"):
			_arms.append(child)
			child._setup(_player)

	# Activar el primer brazo, desactivar el resto
	for i in _arms.size():
		if i == 0:
			_arms[i].set_physics_process(true)
			_arms[i].visible = true
		else:
			_arms[i].set_physics_process(false)
			_arms[i].visible = false

	if _arms.size() > 0:
		current_arm = _arms[0]
		print("ArmSocket: equipado '%s'" % current_arm.name)


func primary_action() -> void:
	if current_arm and current_arm.has_method("primary_action"):
		current_arm.primary_action()


func secondary_action() -> void:
	if current_arm and current_arm.has_method("secondary_action"):
		current_arm.secondary_action()


func release_action() -> void:
	if current_arm and current_arm.has_method("release_action"):
		current_arm.release_action()


## Rotar al siguiente brazo disponible
func switch_arm() -> void:
	if _arms.size() <= 1:
		return

	# Cancelar accion del brazo actual
	_cancel_current_arm()

	# Desactivar brazo actual
	if current_arm:
		current_arm.set_physics_process(false)
		current_arm.visible = false

	# Rotar indice
	_current_index = (_current_index + 1) % _arms.size()
	current_arm = _arms[_current_index]

	# Activar nuevo brazo
	current_arm.set_physics_process(true)
	current_arm.visible = true
	print("ArmSocket: cambiado a '%s'" % current_arm.name)


## Cancela la accion activa del brazo actual
func _cancel_current_arm() -> void:
	if not current_arm:
		return
	if current_arm.has_method("cancel_punch"):
		current_arm.cancel_punch()
	if current_arm.has_method("cancel_hook"):
		current_arm.cancel_hook()
