class_name StateMachine extends Node

## StateMachine generica y reutilizable.
## Registra sus hijos State, maneja transiciones y delega _physics_process,
## _process y _unhandled_input al estado activo.

@export var initial_state: State

var current_state: State
var states: Dictionary = {}


func _ready():
	# Registrar todos los hijos que sean State
	for child in get_children():
		if child is State:
			states[child.name] = child
			child.state_machine = self
	# Diferir la entrada al estado inicial para que el nodo padre
	# (ej: Player) ya tenga sus @onready vars inicializadas
	_enter_initial_state.call_deferred()


func _enter_initial_state():
	if initial_state:
		current_state = initial_state
		current_state.enter()


func _physics_process(delta: float):
	if current_state:
		current_state.process_physics(delta)


func _unhandled_input(event: InputEvent):
	if current_state:
		current_state.process_input(event)


func _process(delta: float):
	if current_state:
		current_state.process_frame(delta)


func transition_to(state_name: String, params := {}):
	if not states.has(state_name):
		push_warning("StateMachine: State '%s' no encontrado" % state_name)
		return
	if current_state:
		current_state.exit()
	current_state = states[state_name]
	current_state.enter(params)
