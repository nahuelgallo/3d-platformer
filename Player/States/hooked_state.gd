class_name HookedState extends State

## Estado enganchado al grappling hook. Comportamiento depende de la superficie:
## - Techo (normal.y < -0.3): pendulo — swing con gravedad
## - Pared (abs(normal.y) <= 0.3): recoil — atrae al jugador hacia el punto
## - Piso (normal.y > 0.3): fast pull — atrae hacia abajo mas rapido que gravedad
## Integra rope wrapping: la cuerda se curva alrededor de objetos.

enum HookMode { PENDULUM, WALL_RECOIL, WALL_CLING, FLOOR_PULL }

const AIR_CONTROL := 12.0
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
const PENDULUM_DAMPING := 0.995   # Damping por frame, muy suave para no frenar el swing
const AUTO_RETRACT_RATIO := 0.75  # Al engancharse, acortar cuerda al 75% para no chocar con el piso
const MIN_GROUND_CLEARANCE := 2.0 # Metros minimos entre el jugador colgado y el piso
const RETRACT_LERP_SPEED := 4.0   # Velocidad de acortamiento suave de la cuerda
const PENDULUM_STEP_HEIGHT := 0.5 # Altura de escalon que puede subir pendulando

var player: CharacterBody3D
var _attach_point := Vector3.ZERO
var _rope_length := 0.0
var _target_rope_length := 0.0    # Largo objetivo (para lerp suave)
var _surface_normal := Vector3.DOWN
var _mode := HookMode.PENDULUM
var _rope_wrap: RopeWrap = null


func enter(params := {}):
	if not player:
		player = state_machine.get_parent()
	_attach_point = params.get("attach_point", Vector3.ZERO)
	_rope_length = params.get("rope_length", 5.0)
	_surface_normal = params.get("surface_normal", Vector3.DOWN)
	var is_hook_ring: bool = params.get("is_hook_ring", false)

	# Hook rings siempre son pendulo, sin importar la normal
	if is_hook_ring:
		_mode = HookMode.PENDULUM
	elif _surface_normal.y < CEILING_THRESHOLD:
		_mode = HookMode.PENDULUM
	elif _surface_normal.y > FLOOR_THRESHOLD:
		_mode = HookMode.FLOOR_PULL
	else:
		_mode = HookMode.WALL_RECOIL

	# Auto-retract: calcular largo objetivo que garantiza clearance sobre el piso
	if _mode == HookMode.PENDULUM:
		_target_rope_length = _rope_length * AUTO_RETRACT_RATIO
		# Raycast hacia abajo desde el attach point para encontrar el suelo
		var space = player.get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(
			_attach_point, _attach_point + Vector3.DOWN * 100.0
		)
		query.collision_mask = 1  # Solo world geometry
		query.exclude = [player.get_rid()]
		var result = space.intersect_ray(query)
		if result:
			var ground_y: float = result.position.y
			var max_rope_for_clearance = _attach_point.y - ground_y - MIN_GROUND_CLEARANCE
			if max_rope_for_clearance > MIN_ROPE_LENGTH:
				_target_rope_length = minf(_target_rope_length, max_rope_for_clearance)
		# NO acortar instantaneamente — _rope_length se lerpa en _process_pendulum
	else:
		_target_rope_length = _rope_length

	# Inicializar rope wrapping (solo para pendulo, los otros modos son cortos)
	if _mode == HookMode.PENDULUM:
		_rope_wrap = RopeWrap.new()
		_rope_wrap.initialize(_attach_point, player.global_position)
		_rope_wrap.total_rope_length = _rope_length
	else:
		_rope_wrap = null

	# Aumentar tolerancia de escalones durante pendulo
	if _mode == HookMode.PENDULUM:
		player.floor_snap_length = PENDULUM_STEP_HEIGHT
		player.floor_max_angle = deg_to_rad(60.0)

	# Camara
	player._target_camera_distance = player.camera_sprint_distance
	player._target_camera_fov = HOOKED_FOV

	# Animacion
	player._skin.fall()

	print("HookedState: modo=%s, normal=%s" % [HookMode.keys()[_mode], _surface_normal])


func exit():
	player._target_camera_distance = player.camera_default_distance
	player._target_camera_fov = player.camera_default_fov
	# Restaurar tolerancia de escalones al default del player
	player.floor_snap_length = 0.4
	player.floor_max_angle = deg_to_rad(45.0)
	_rope_wrap = null


func process_physics(delta: float):
	match _mode:
		HookMode.PENDULUM:
			_process_pendulum(delta)
		HookMode.WALL_RECOIL:
			_process_wall_recoil(delta)
		HookMode.WALL_CLING:
			_process_wall_cling(delta)
		HookMode.FLOOR_PULL:
			_process_floor_pull(delta)

	# Rotar skin
	player.rotate_skin(delta)

	# --- TRANSICIONES COMUNES ---

	# Re-lanzar hook: left click suelta el actual y empieza a cargar uno nuevo
	if _mode == HookMode.PENDULUM and Input.is_action_just_pressed("left_click"):
		_notify_arm_release()
		state_machine.transition_to("Airborne", {"jumped": false, "from_hook": true})
		# Disparar primary_action inmediatamente para empezar a cargar el nuevo hook
		if player._arm_socket:
			player._arm_socket.primary_action()
		return

	# Wall cling: left click suelta para poder re-lanzar hook
	if _mode == HookMode.WALL_CLING and Input.is_action_just_pressed("left_click"):
		_notify_arm_release()
		# Salto leve desde la pared para poder re-enganchar
		player.velocity = _surface_normal * 5.0 + Vector3.UP * 3.0
		state_machine.transition_to("Airborne", {"jumped": true, "from_hook": true})
		return

	# Saltar: impulso y salir
	if player.jump_buffer_timer > 0.0:
		player.jump_buffer_timer = 0.0
		# Wall cling: salto desde la pared (impulso perpendicular + arriba)
		if _mode == HookMode.WALL_CLING:
			player.velocity = _surface_normal * 8.0 + Vector3.UP * player.jump_impulse * RELEASE_JUMP_MULT
		else:
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
	# Retraccion suave: lerp de rope_length hacia target
	if _rope_length > _target_rope_length + 0.1:
		_rope_length = lerpf(_rope_length, _target_rope_length, RETRACT_LERP_SPEED * delta)
		if _rope_wrap:
			_rope_wrap.total_rope_length = _rope_length

	# Gravedad
	player.apply_gravity(delta)

	# Subir/bajar cuerda (modifica el target tambien)
	if Input.is_action_pressed("sprint"):
		_target_rope_length = max(_target_rope_length - CLIMB_SPEED * delta, MIN_ROPE_LENGTH)
		_rope_length = max(_rope_length - CLIMB_SPEED * delta, MIN_ROPE_LENGTH)
		if _rope_wrap:
			_rope_wrap.total_rope_length = _rope_length
	elif Input.is_action_pressed("crouch"):
		_target_rope_length += CLIMB_SPEED * delta
		_rope_length += CLIMB_SPEED * delta
		if _rope_wrap:
			_rope_wrap.total_rope_length = _rope_length

	# Control aereo minimo
	var move_dir = player.get_move_direction()
	if move_dir.length() > 0.1:
		player.velocity.x += move_dir.x * AIR_CONTROL * delta
		player.velocity.z += move_dir.z * AIR_CONTROL * delta

	# Constraint de cuerda ANTES de move_and_slide para evitar inyectar energia
	var pivot = _get_current_pivot()
	var effective_length = _get_effective_rope_length()
	var to_player = player.global_position - pivot
	var distance = to_player.length()
	if distance > effective_length:
		player.global_position = pivot + to_player.normalized() * effective_length
		# Solo remover velocidad radial saliente
		var radial_dir = to_player.normalized()
		var radial_vel = player.velocity.dot(radial_dir)
		if radial_vel > 0.0:
			player.velocity -= radial_dir * radial_vel

	# Damping: reducir velocidad ligeramente cada frame para evitar amplificacion
	player.velocity *= PENDULUM_DAMPING

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

	# Constraint post-move: corregir si move_and_slide desplazo al player fuera del radio
	var post_pivot = _get_current_pivot()
	var post_length = _get_effective_rope_length()
	var post_to_player = player.global_position - post_pivot
	if post_to_player.length() > post_length:
		player.global_position = post_pivot + post_to_player.normalized() * post_length


## ============================================================
## WALL RECOIL — Pared: atrae al jugador hacia el punto
## ============================================================
func _process_wall_recoil(delta: float):
	var target = _attach_point
	var to_target = target - player.global_position
	var distance = to_target.length()

	# Llego al punto — transicionar a wall cling (pegado a la pared)
	if distance < ARRIVAL_DISTANCE:
		player.velocity = Vector3.ZERO
		_mode = HookMode.WALL_CLING
		player._skin.idle()
		print("HookedState: wall cling activado")
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
## WALL CLING — Pegado a la pared: puede re-lanzar hook o saltar
## ============================================================
func _process_wall_cling(_delta: float):
	# El jugador esta pegado al punto de enganche, sin gravedad
	# Mantener posicion cerca del attach point
	var to_attach = _attach_point - player.global_position
	if to_attach.length() > 0.5:
		player.global_position = _attach_point - _surface_normal * 0.5

	player.velocity = Vector3.ZERO
	# No llamar move_and_slide — el jugador esta fijo

	# Visual
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
