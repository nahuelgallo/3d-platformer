class_name HookedState extends State

## Estado enganchado al grappling hook. Comportamiento depende de la superficie:
## - Techo (normal.y < -0.3): pendulo — swing con gravedad
## - Pared (abs(normal.y) <= 0.3): recoil — atrae al jugador hacia el punto
## - Piso (normal.y > 0.3): fast pull — atrae hacia abajo mas rapido que gravedad
## Integra rope wrapping: la cuerda se curva alrededor de objetos.

enum HookMode { PENDULUM, WALL_RECOIL, FLOOR_PULL }

const AIR_CONTROL := 3.0
const RELEASE_JUMP_MULT := 0.7
const RECOIL_SPEED := 25.0
const HOOKED_FOV := 85.0
const CLIMB_SPEED := 5.0
const MIN_ROPE_LENGTH := 1.5

# Umbrales de normal para clasificar superficie
const CEILING_THRESHOLD := -0.3   # normal.y < esto = techo
const FLOOR_THRESHOLD := 0.3      # normal.y > esto = piso

# Parametros por modo
const WALL_RECOIL_SPEED := 25.0   # Velocidad de atraccion a paredes
const FLOOR_PULL_SPEED := 40.0    # Velocidad de atraccion a piso
const FLOOR_PULL_GRAVITY_MULT := 2.5
const ARRIVAL_DISTANCE := 1.5     # Distancia a la que se considera "llegado" al punto

var player: CharacterBody3D
var _attach_point := Vector3.ZERO
var _rope_length := 0.0
var _surface_normal := Vector3.DOWN
var _mode := HookMode.PENDULUM
var _rope_wrap: RopeWrap = null


func enter(params := {}):
	if not player:
		player = state_machine.get_parent()
	_attach_point = params.get("attach_point", Vector3.ZERO)
	_rope_length = params.get("rope_length", 5.0)
	_surface_normal = params.get("surface_normal", Vector3.DOWN)

	# Clasificar el modo segun la normal de la superficie
	if _surface_normal.y < CEILING_THRESHOLD:
		_mode = HookMode.PENDULUM
	elif _surface_normal.y > FLOOR_THRESHOLD:
		_mode = HookMode.FLOOR_PULL
	else:
		_mode = HookMode.WALL_RECOIL

	# Inicializar rope wrapping (solo para pendulo, los otros modos son cortos)
	if _mode == HookMode.PENDULUM:
		_rope_wrap = RopeWrap.new()
		_rope_wrap.initialize(_attach_point, player.global_position)
	else:
		_rope_wrap = null

	# Camara
	player._target_camera_distance = player.camera_sprint_distance
	player._target_camera_fov = HOOKED_FOV

	# Animacion
	player._skin.fall()

	print("HookedState: modo=%s, normal=%s" % [HookMode.keys()[_mode], _surface_normal])


func exit():
	player._target_camera_distance = player.camera_default_distance
	player._target_camera_fov = player.camera_default_fov
	_rope_wrap = null


func process_physics(delta: float):
	match _mode:
		HookMode.PENDULUM:
			_process_pendulum(delta)
		HookMode.WALL_RECOIL:
			_process_wall_recoil(delta)
		HookMode.FLOOR_PULL:
			_process_floor_pull(delta)

	# Rotar skin
	player.rotate_skin(delta)

	# --- TRANSICIONES COMUNES ---

	# Recoil manual: left click lanza hacia el attach point (solo en pendulo)
	if _mode == HookMode.PENDULUM and Input.is_action_just_pressed("left_click"):
		var pivot = _get_current_pivot()
		var recoil_dir = (pivot - player.global_position).normalized()
		player.velocity = recoil_dir * RECOIL_SPEED
		_notify_arm_release()
		state_machine.transition_to("Airborne", {"jumped": true, "boosted": true, "from_hook": true})
		return

	# Saltar: impulso y salir
	if player.jump_buffer_timer > 0.0:
		player.jump_buffer_timer = 0.0
		player.velocity.y += player.jump_impulse * RELEASE_JUMP_MULT
		_notify_arm_release()
		state_machine.transition_to("Airborne", {"jumped": true, "from_hook": true})
		return

	# Tocar suelo (solo en pendulo — recoil y pull terminan de otra forma)
	if _mode == HookMode.PENDULUM and player.is_on_floor():
		_notify_arm_release()
		var h_speed = Vector2(player.velocity.x, player.velocity.z).length()
		if h_speed > 0.5:
			state_machine.transition_to("Walk")
		else:
			state_machine.transition_to("Idle")
		return


## ============================================================
## PENDULUM — Techo/overhang: swing clasico con rope wrapping
## ============================================================
func _process_pendulum(delta: float):
	# Gravedad
	player.apply_gravity(delta)

	# Subir/bajar cuerda
	if Input.is_action_pressed("sprint"):
		_rope_length = max(_rope_length - CLIMB_SPEED * delta, MIN_ROPE_LENGTH)
	elif Input.is_action_pressed("crouch"):
		_rope_length += CLIMB_SPEED * delta

	# Control aereo minimo
	var move_dir = player.get_move_direction()
	if move_dir.length() > 0.1:
		player.velocity.x += move_dir.x * AIR_CONTROL * delta
		player.velocity.z += move_dir.z * AIR_CONTROL * delta

	player.move_and_slide()

	# Rope wrapping: actualizar wrap points
	if _rope_wrap:
		var space = player.get_world_3d().direct_space_state
		_rope_wrap.update(player.global_position, space, player.get_rid())

		# Actualizar rope visual con multi-segmento
		var arm = _get_arm()
		if arm and arm._rope:
			var points = _rope_wrap.get_all_points(player.global_position)
			# Reemplazar el primer punto con la posicion de la mano
			if points.size() > 0:
				points[-1] = arm._get_hand_position()
			arm._rope.update_multi_segment(points)

	# Constraint de cuerda usando el pivot activo (ultimo wrap point)
	var pivot = _get_current_pivot()
	var effective_length = _get_effective_rope_length()
	var to_player = player.global_position - pivot
	var distance = to_player.length()
	if distance > effective_length:
		var clamped_pos = pivot + to_player.normalized() * effective_length
		player.global_position = clamped_pos

		var radial_dir = to_player.normalized()
		var radial_vel = player.velocity.dot(radial_dir)
		if radial_vel > 0.0:
			player.velocity -= radial_dir * radial_vel


## ============================================================
## WALL RECOIL — Pared: atrae al jugador hacia el punto
## ============================================================
func _process_wall_recoil(delta: float):
	var target = _attach_point
	var to_target = target - player.global_position
	var distance = to_target.length()

	# Llego al punto — soltar automaticamente
	if distance < ARRIVAL_DISTANCE:
		player.velocity = to_target.normalized() * 5.0  # Impulso residual
		_notify_arm_release()
		state_machine.transition_to("Airborne", {"jumped": true, "from_hook": true})
		return

	# Mover hacia el punto de enganche
	var pull_dir = to_target.normalized()
	player.velocity = pull_dir * WALL_RECOIL_SPEED

	# Gravedad reducida durante el recoil
	player.velocity.y += player._gravity * 0.3 * delta

	player.move_and_slide()

	# Visual: linea recta (sin wrapping para recoil)
	var arm = _get_arm()
	if arm and arm._rope:
		arm._rope.update_points(arm._get_hand_position(), _attach_point)


## ============================================================
## FLOOR PULL — Piso: atrae hacia abajo rapido
## ============================================================
func _process_floor_pull(delta: float):
	var target = _attach_point
	var to_target = target - player.global_position
	var distance = to_target.length()

	# Llego al punto — aterrizar
	if distance < ARRIVAL_DISTANCE or player.is_on_floor():
		player.velocity = Vector3.ZERO
		_notify_arm_release()
		state_machine.transition_to("Idle")
		return

	# Mover hacia el punto con velocidad alta
	var pull_dir = to_target.normalized()
	player.velocity = pull_dir * FLOOR_PULL_SPEED

	# Gravedad extra para que se sienta como un pull rapido
	player.velocity.y += player._gravity * FLOOR_PULL_GRAVITY_MULT * delta

	player.move_and_slide()

	# Visual
	var arm = _get_arm()
	if arm and arm._rope:
		arm._rope.update_points(arm._get_hand_position(), _attach_point)


## ============================================================
## HELPERS
## ============================================================

func _get_current_pivot() -> Vector3:
	if _rope_wrap:
		return _rope_wrap.get_active_pivot()
	return _attach_point


func _get_effective_rope_length() -> float:
	if _rope_wrap:
		return _rope_wrap.get_effective_rope_length()
	return _rope_length


func _get_arm() -> GrapplingHookArm:
	if player._arm_socket and player._arm_socket.current_arm is GrapplingHookArm:
		return player._arm_socket.current_arm as GrapplingHookArm
	return null


func _notify_arm_release():
	if player._arm_socket and player._arm_socket.current_arm:
		var arm = player._arm_socket.current_arm
		if arm.has_method("cancel_hook"):
			arm.cancel_hook()
