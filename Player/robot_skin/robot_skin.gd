class_name RobotSkin extends Node3D

# Controlador de animaciones del robot.
# Usa un AnimationTree con StateMachine para manejar transiciones suaves.
# Las animaciones se manipulan en runtime porque los GLB importados son read-only.

@onready var animation_tree = %AnimationTree
@onready var anim_player : AnimationPlayer = $robot/AnimationPlayer
@onready var state_machine : AnimationNodeStateMachinePlayback = animation_tree.get("parameters/StateMachine/playback")

var is_landing := false      # True mientras se reproduce la animacion de aterrizaje
var _current_state := ""     # Estado actual del StateMachine (para evitar travel() redundantes)
var _player: CharacterBody3D  # Referencia al player, seteada en _ready

const LAND_THRESHOLD := 18.0  # Velocidad minima de caida para activar animacion de landing

func _ready():
	# Buscar el Player subiendo por el arbol
	var node = get_parent()
	while node and not node is CharacterBody3D:
		node = node.get_parent()
	_player = node
	_setup_animations()
	# Forzar al AnimationTree a reiniciar despues de reemplazar animaciones.
	# Sin esto, el tree puede mantener referencias a las animaciones viejas (ya eliminadas).
	animation_tree.active = false
	animation_tree.active = true
	# Necesitamos re-obtener la referencia al playback despues del reinicio.
	state_machine = animation_tree.get("parameters/StateMachine/playback")

# Configura loop modes y crea animaciones derivadas.
# Se hace en runtime porque las animaciones importadas de GLB son recursos read-only.
# La solucion es duplicarlas, modificar la copia, y reemplazar la original en la libreria.
func _setup_animations():
	var lib = anim_player.get_animation_library("")

	# Idle: ping-pong (respira hacia adelante y luego en reversa, ida y vuelta)
	_replace_with_loop_mode(lib, "Robot_Idle_Breathe", Animation.LOOP_PINGPONG)

	# Walk, run, crouch walk, strafe: loop lineal (se repite constantemente)
	for anim_name in ["Robot_walk_ZBounce", "Robot_Run", "Robot_Crouch_Walk", "Robot_Strafe_Left", "Robot_Strafe_Right"]:
		_replace_with_loop_mode(lib, anim_name, Animation.LOOP_LINEAR)

	# Punch: una sola reproduccion (no loopea)
	_replace_with_loop_mode(lib, "Robot_Punch", Animation.LOOP_NONE)

	# Slide: una sola reproduccion (no loopea)
	_replace_with_loop_mode(lib, "Robot_Slide", Animation.LOOP_NONE)

	# Separar Robot_Crouch_Idle en dos animaciones:
	# - Crouch_Begin (frames 0-18): transicion de parado a agachado, se reproduce una vez
	# - Crouch_Idle_Loop (frames 26-29): idle agachado que se repite
	var crouch_full = lib.get_animation("Robot_Crouch_Idle")
	if crouch_full:
		var fps := 30.0

		var begin = crouch_full.duplicate()
		_trim_animation(begin, 0.0, 19.0 / fps)
		begin.loop_mode = Animation.LOOP_NONE
		lib.add_animation("Crouch_Begin", begin)

		var idle_loop = crouch_full.duplicate()
		_trim_animation(idle_loop, 26.0 / fps, 30.0 / fps)
		idle_loop.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation("Crouch_Idle_Loop", idle_loop)

	# Debug: verificar que todas las animaciones existen despues del setup
	print("=== RobotSkin: Animaciones configuradas ===")
	for anim_name in ["Robot_Idle_Breathe", "Robot_walk_ZBounce", "Robot_Run", "Robot_Crouch_Walk", "Crouch_Begin", "Crouch_Idle_Loop", "Robot_Punch", "Robot_Slide", "Robot_Strafe_Left", "Robot_Strafe_Right"]:
		var a = lib.get_animation(anim_name)
		if a:
			print("  OK: '%s' (loop=%d, length=%.2fs)" % [name, a.loop_mode, a.length])
		else:
			print("  FALTA: '%s'" % anim_name)

# Duplica una animacion, le cambia el loop mode, y reemplaza la original.
# Necesario porque los recursos importados de GLB no se pueden modificar directamente.
func _replace_with_loop_mode(lib: AnimationLibrary, anim_name: String, mode: int):
	var anim = lib.get_animation(anim_name)
	if not anim:
		push_warning("RobotSkin: Animacion '%s' no encontrada" % anim_name)
		return
	var copy = anim.duplicate()
	copy.loop_mode = mode
	lib.remove_animation(anim_name)
	lib.add_animation(anim_name, copy)

# Recorta una animacion para que solo contenga el rango [start_time, end_time].
# Elimina keyframes fuera del rango y ajusta los tiempos de los restantes.
func _trim_animation(anim: Animation, start_time: float, end_time: float):
	anim.length = end_time - start_time
	for track_idx in anim.get_track_count():
		# Eliminar keys fuera del rango (iterar en reversa para no romper indices)
		for key_idx in range(anim.track_get_key_count(track_idx) - 1, -1, -1):
			var time = anim.track_get_key_time(track_idx, key_idx)
			if time < start_time or time > end_time:
				anim.track_remove_key(track_idx, key_idx)
		# Mover keys restantes para que arranquen desde 0
		for key_idx in anim.track_get_key_count(track_idx):
			var time = anim.track_get_key_time(track_idx, key_idx)
			anim.track_set_key_time(track_idx, key_idx, time - start_time)

# Transiciona al estado solo si no estamos ya en el.
# Evita llamar travel() cada frame, lo cual resetea la animacion.
# Bloqueado durante el punch para que los estados de movimiento no lo pisen.
func _travel(state: String):
	if _current_state == "Punch":
		return
	if _current_state == state:
		return
	_current_state = state
	print("RobotSkin -> travel('%s')" % state)  # Debug: ver transiciones en consola
	state_machine.travel(state)

# === FUNCIONES PUBLICAS ===
# El player controller llama estas funciones segun el estado del movimiento.

func idle():
	_travel("Idle")

func move():
	_travel("Move")

func run():
	_travel("Run")

func fall():
	_travel("Fall")

func jump():
	_travel("Jump")

func crouch():
	# Si ya estamos agachados (begin o idle loop), no hacer nada
	if _current_state in ["CrouchBegin", "Crouch"]:
		return
	# Desde crouch walk: ir directo al idle loop (sin repetir la animacion de begin)
	if _current_state == "CrouchWalk":
		_current_state = "Crouch"
		state_machine.travel("Crouch")
	else:
		# Primera vez agachandose: reproducir animacion de transicion
		_current_state = "CrouchBegin"
		state_machine.travel("CrouchBegin")

func crouch_walk():
	_travel("CrouchWalk")

func strafe_left():
	_travel("StrafeLeft")

func strafe_right():
	_travel("StrafeRight")

func slide():
	if _current_state != "Slide":
		_current_state = "Slide"
		state_machine.start("Slide")


func punch():
	# Animacion de golpe: reproduce Punch y vuelve al estado anterior al terminar.
	# Si otro estado interrumpe (dash, slide), cancel_punch() limpia _current_state
	# y el await de abajo no hace nada al volver.
	_current_state = "Punch"
	_player.is_punching = true
	state_machine.start("Punch")
	var punch_anim = anim_player.get_animation("Robot_Punch")
	var duration := 0.4
	if punch_anim:
		duration = punch_anim.length
	await get_tree().create_timer(duration).timeout
	# Siempre limpiar is_punching al terminar el timer
	_player.is_punching = false
	# Solo volver a Idle si seguimos en Punch (no fue interrumpido por land/dash/etc)
	if _current_state == "Punch":
		_current_state = ""
		state_machine.travel("Idle")


func cancel_punch():
	# Interrumpe el punch inmediatamente (llamado por dash/slide/etc)
	if _current_state == "Punch":
		_current_state = ""
		_player.is_punching = false

# Landing: animacion de impacto al tocar el suelo tras una caida fuerte.
# Bloquea el movimiento del jugador durante la animacion (el robot es pesado).
# fall_speed: velocidad absoluta de caida al momento del impacto.
func land(fall_speed: float):
	if fall_speed < LAND_THRESHOLD:
		return
	is_landing = true
	_current_state = "Land"
	# Cuanto mas alta la caida, mas dura el landing (pero con un tope maximo)
	var extra_speed = fall_speed - LAND_THRESHOLD
	var duration = 0.1 + clamp(extra_speed * 0.015, 0.0, 0.4)
	state_machine.travel("Land")
	anim_player.speed_scale = 3.0  # Acelerar la animacion para que no se sienta lenta
	await get_tree().create_timer(duration).timeout
	anim_player.speed_scale = 1.0
	is_landing = false
	_current_state = ""
	state_machine.travel("Idle")
