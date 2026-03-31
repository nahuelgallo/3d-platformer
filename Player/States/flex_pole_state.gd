class_name FlexPoleState extends State

## Estado del jugador cuando esta enganchado a un FlexPole.
## El jugador se queda en el SUELO, agarrado al palo via la cuerda del hook.
## S = alejarse del palo (doblar, aumentar potencia).
## W = acercarse (reducir doblez).
## A/D = orbitar alrededor del palo (cambiar direccion de lanzamiento).
## Jump = catapulta. Gravedad y move_and_slide siguen activos.

const ORBIT_SPEED := 1.5          # Velocidad de orbita alrededor del palo (rad/sec)
const MIN_DISTANCE := 2.0         # Distancia minima al palo
const MAX_PULL_BACK := 5.0        # Cuanto se puede alejar del punto inicial
const MOVE_SPEED := 6.0           # Velocidad al alejarse/acercarse del palo
const BEND_PER_DISTANCE := 1.5    # Velocidad de doblez por segundo

var player: CharacterBody3D
var _flex_pole: FlexPole = null
var _orbit_angle: float = 0.0     # Angulo actual alrededor del palo (radianes)
var _current_distance: float = 2.0  # Distancia actual al palo
var _initial_distance: float = 2.0  # Distancia al momento de engancharse
var _bend_amount: float = 0.0


func enter(params := {}):
	if not player:
		player = state_machine.get_parent()

	_flex_pole = params.get("flex_pole", null)
	if not _flex_pole:
		push_warning("FlexPoleState: no flex_pole in params, returning to Airborne")
		state_machine.transition_to("Airborne")
		return

	_bend_amount = 0.0

	# Calcular angulo y distancia inicial basado en posicion actual del jugador
	var to_player = player.global_position - _flex_pole.global_position
	to_player.y = 0.0  # Solo en el plano horizontal
	_orbit_angle = atan2(to_player.x, to_player.z)
	_current_distance = to_player.length()  # Quedarse donde esta, sin clampear
	_initial_distance = _current_distance

	# Notificar al pole que fue agarrado, con la altura del hit
	var hit_y = params.get("hit_y", -1.0)
	_flex_pole.grab(player, hit_y)

	# Animacion — el jugador esta en el suelo, no colgando
	player._skin.idle()

	# Camara se aleja un poco para ver el palo
	player._target_camera_distance = 5.0
	player._target_camera_fov = 80.0

	print("FlexPoleState: agarrado a pole, distancia=%.1f, angulo=%.1f" % [_current_distance, rad_to_deg(_orbit_angle)])


func exit():
	if _flex_pole:
		_flex_pole.release()
		_flex_pole = null
	_bend_amount = 0.0

	# Restaurar camara
	if player:
		player._target_camera_distance = player.camera_default_distance
		player._target_camera_fov = player.camera_default_fov


func process_physics(delta: float):
	if not _flex_pole:
		state_machine.transition_to("Airborne")
		return

	var input_raw = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# --- ORBITAR (A/D) ---
	if abs(input_raw.x) > 0.1:
		_orbit_angle += input_raw.x * ORBIT_SPEED * delta

	# --- S = doblar (alejarse) / W = soltar (acercarse) ---
	var max_distance = _initial_distance + MAX_PULL_BACK
	if input_raw.y > 0.1 and _bend_amount < 1.0:
		# S: alejarse del palo y doblar (solo si no esta al maximo)
		_current_distance = minf(_current_distance + MOVE_SPEED * delta, max_distance)
		_bend_amount = minf(_bend_amount + BEND_PER_DISTANCE * delta, 1.0)
	elif input_raw.y < -0.1:
		# W: acercarse al palo y soltar doblez
		_current_distance = maxf(_current_distance - MOVE_SPEED * delta, MIN_DISTANCE)
		_bend_amount = maxf(_bend_amount - BEND_PER_DISTANCE * delta, 0.0)

	# Calcular posicion horizontal del jugador en el suelo
	var pole_pos = _flex_pole.global_position
	var target_pos = pole_pos + Vector3(
		sin(_orbit_angle) * _current_distance,
		0.0,
		cos(_orbit_angle) * _current_distance
	)
	# Mantener la Y del jugador (gravedad lo pone en el suelo)
	target_pos.y = player.global_position.y

	# Mover al jugador hacia la posicion orbital usando velocity + move_and_slide
	var move_dir = (target_pos - player.global_position)
	move_dir.y = 0.0
	if move_dir.length() > 0.1:
		player.velocity.x = move_dir.x * 15.0  # Snap rapido a posicion orbital
		player.velocity.z = move_dir.z * 15.0
	else:
		player.velocity.x = 0.0
		player.velocity.z = 0.0

	# Gravedad normal para que se quede en el suelo
	player.apply_gravity(delta)
	player.move_and_slide()

	# Actualizar el doblez visual del palo
	var player_dir = (player.global_position - pole_pos)
	player_dir.y = 0.0
	if player_dir.length() > 0.1:
		_flex_pole.update_bend(_bend_amount, player_dir.normalized())

	# Rotar skin mirando al palo
	var look_dir = (pole_pos - player.global_position)
	look_dir.y = 0.0
	if look_dir.length() > 0.1:
		var target_angle = Vector3.BACK.signed_angle_to(look_dir.normalized(), Vector3.UP)
		player._skin.global_rotation.y = lerp_angle(
			player._skin.global_rotation.y, target_angle, 10.0 * delta
		)

	# Rotar skin con animacion de caminar si se mueve
	if abs(input_raw.x) > 0.1 or abs(input_raw.y) > 0.1:
		player._skin.move()
	else:
		player._skin.idle()

	# --- TRANSICIONES ---

	# Saltar = catapulta
	if player.jump_buffer_timer > 0.0:
		player.jump_buffer_timer = 0.0
		var launch_vel = _flex_pole.calculate_launch_velocity(player.global_position)
		player.velocity = launch_vel
		Events.pole_launched.emit(launch_vel)
		player.apply_squash_and_stretch(Vector3(0.7, 1.4, 0.7))
		_notify_arm_release()
		state_machine.transition_to("Airborne", {"jumped": true, "boosted": true, "from_hook": true})
		return

	# Soltar hook (click) = soltar sin catapulta
	if Input.is_action_just_pressed("left_click"):
		_notify_arm_release()
		if player.is_on_floor():
			state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Airborne")
		return


## Notifica al brazo que se solto el gancho
func _notify_arm_release():
	if player._arm_socket and player._arm_socket.current_arm:
		var arm = player._arm_socket.current_arm
		if arm.has_method("cancel_hook"):
			arm.cancel_hook()
