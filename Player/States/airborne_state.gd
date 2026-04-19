class_name AirborneState extends State

## Estado aereo. Control limitado, momentum se conserva.
## Maneja coyote time, jump cut, y deteccion de aterrizaje.

const AIR_ACCELERATION := 5.0
const AIR_FRICTION := 0.5
const FAST_DROP_SPEED := -50.0  # Velocidad de caida rapida al agacharse en el aire
const AIR_DASH_BOOST := 2.0  # Multiplicador de velocidad para air dash
const AIR_DASH_MIN_SPEED := 22.0  # Velocidad minima garantizada del air dash
const EXPLOSIVE_PHASE_DURATION := 0.2  # 200ms sin friccion post-slide-jump
const DECAY_FRICTION := 3.0  # Friccion durante decaimiento (mas alta que AIR_FRICTION)
const SKIP_LEDGE_DURATION := 0.3  # Anti re-grab timer despues de soltar cornisa
const HOOK_FLOATY_GRAVITY := 0.6  # Multiplicador de gravedad post-hook (40% mas floaty)
const HOOK_FLOATY_DURATION := 1.5 # Segundos de gravedad reducida post-hook
const BULLET_TIME_SCALE := 0.25   # Escala de tiempo durante bullet time (25% velocidad)
const BULLET_TIME_DURATION := 1.5 # Duracion maxima del bullet time
const LEDGE_CHEST_HEIGHT := 1.5
const LEDGE_HEAD_HEIGHT := 2.4
const LEDGE_RAY_LENGTH := 0.7
const LEDGE_MIN_FALL_SPEED := 1.0

var player: CharacterBody3D
var _did_fast_drop := false
var _did_air_dash := false
var _from_slide_jump := false
var _chain_count := 0
var _explosive_timer := 0.0  # Timer de la fase explosiva
var _is_boosted_jump := false  # Si viene de slide jump o dash
var _skip_ledge_grab := false  # Anti re-grab despues de soltar cornisa
var _skip_ledge_timer := 0.0
var _from_hook := false         # Si viene de un hook/pole launch
var _hook_floaty_timer := 0.0   # Timer de gravedad reducida post-hook
var _bullet_time_active := false # Bullet time activo
var _bullet_time_timer := 0.0   # Timer de bullet time restante
var _crouch_tap_count := 0      # Cantidad de taps de crouch para fast fall
var _crouch_tap_timer := 0.0    # Timer para detectar doble tap
const DOUBLE_TAP_WINDOW := 0.35 # Ventana de tiempo para doble tap


func enter(params := {}):
	if not player:
		player = state_machine.get_parent()
	_did_fast_drop = false
	# Anti re-grab: evita agarrar cornisa inmediatamente despues de soltar
	_skip_ledge_grab = params.get("skip_ledge_grab", false)
	_skip_ledge_timer = SKIP_LEDGE_DURATION if _skip_ledge_grab else 0.0
	# Air dash: disponible si no viene de slide jump o dash directo
	# Desde hook/pole (from_hook=true) el dash SI esta disponible
	var from_hook = params.get("from_hook", false)
	_did_air_dash = params.get("boosted", false) and not from_hook
	_from_slide_jump = params.get("from_slide_jump", false)
	_chain_count = params.get("chain_count", 0)

	# Fase explosiva: si viene de slide jump o dash, activar timer sin friccion
	if params.get("boosted", false):
		_explosive_timer = EXPLOSIVE_PHASE_DURATION
		_is_boosted_jump = true
	else:
		_explosive_timer = 0.0
		_is_boosted_jump = false

	# Gravedad floaty post-hook: si viene de hook o pole, gravedad reducida
	_from_hook = params.get("from_hook", false) or params.get("boosted", false)
	_hook_floaty_timer = HOOK_FLOATY_DURATION if _from_hook else 0.0
	_bullet_time_active = false
	_bullet_time_timer = 0.0
	_crouch_tap_count = 0
	_crouch_tap_timer = 0.0

	# Camara alejada y FOV amplio durante slide jump
	if params.get("boosted", false) or _from_slide_jump:
		player._target_camera_distance = player.camera_sprint_distance
		player._target_camera_fov = player.camera_sprint_fov

	var jumped: bool = params.get("jumped", false)
	if not jumped:
		# Cayo del borde: la animacion de caida se pone cuando velocity.y < 0
		# El coyote_timer ya tiene su valor del ultimo frame en el suelo
		if player.velocity.y < 0:
			player._skin.fall()


func exit():
	_end_bullet_time()


func process_physics(delta: float):
	# Anti re-grab timer para ledge grab
	if _skip_ledge_grab:
		_skip_ledge_timer -= delta
		if _skip_ledge_timer <= 0.0:
			_skip_ledge_grab = false

	# Decrementar coyote timer (solo importa si cayo del borde, no si salto)
	player.coyote_timer -= delta

	# Coyote jump: si todavia hay coyote time y el jugador presiono salto
	if player.coyote_timer > 0.0 and player.jump_buffer_timer > 0.0:
		player.perform_jump()

	# Jump cut: soltar salto corta la velocidad vertical
	if Input.is_action_just_released("jump") and player.velocity.y > 0.0:
		player.velocity.y *= player.jump_cut_multiplier

	# Fast fall: doble tap de crouch en el aire = caida rapida
	if _crouch_tap_timer > 0.0:
		_crouch_tap_timer -= delta
	else:
		_crouch_tap_count = 0

	if Input.is_action_just_pressed("crouch") and not _did_fast_drop:
		_crouch_tap_count += 1
		_crouch_tap_timer = DOUBLE_TAP_WINDOW
		if _crouch_tap_count >= 2:
			player.velocity.y = FAST_DROP_SPEED
			_did_fast_drop = true
			_crouch_tap_count = 0

	# Air dash: sprint en el aire = impulso horizontal (una vez por salto, consume estamina)
	if Abilities.dash_unlocked and Input.is_action_just_pressed("sprint") and not _did_air_dash and Stamina.try_consume(0.5):
		player.cancel_arm_action()
		_did_air_dash = true
		var dash_dir = player.get_move_direction()
		# Si no hay input de movimiento, usar la direccion donde mira el modelo
		if dash_dir.length() < 0.1:
			dash_dir = player._skin.global_basis.z
			dash_dir.y = 0.0
			dash_dir = dash_dir.normalized()
		var h_vel_dash = Vector3(player.velocity.x, 0.0, player.velocity.z)
		var boosted_speed = max(h_vel_dash.length() * AIR_DASH_BOOST, AIR_DASH_MIN_SPEED)
		h_vel_dash = dash_dir * boosted_speed
		player.velocity.x = h_vel_dash.x
		player.velocity.z = h_vel_dash.z
		player._skin.jump()

	# Decrementar explosive timer
	if _explosive_timer > 0.0:
		_explosive_timer -= delta

	# Control aereo con fase explosiva post-slide-jump
	var move_dir = player.get_move_direction()
	var h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if _explosive_timer > 0.0:
		# Fase explosiva: sin friccion, solo permite redirigir ligeramente
		if move_dir.length() > 0.1:
			h_vel = h_vel.move_toward(move_dir * max(h_vel.length(), player.move_speed), AIR_ACCELERATION * delta)
	elif _is_boosted_jump and h_vel.length() > player.sprint_speed:
		# Fase de decaimiento: friccion alta para volver a velocidad normal
		if move_dir.length() > 0.1:
			h_vel = h_vel.move_toward(move_dir * max(h_vel.length(), player.move_speed), AIR_ACCELERATION * delta)
		h_vel = h_vel.move_toward(h_vel.normalized() * player.sprint_speed, DECAY_FRICTION * delta)
	else:
		# Control aereo normal
		if move_dir.length() > 0.1:
			h_vel = h_vel.move_toward(move_dir * max(h_vel.length(), player.move_speed), AIR_ACCELERATION * delta)
		else:
			h_vel = h_vel.move_toward(Vector3.ZERO, AIR_FRICTION * delta)
	player.velocity.x = h_vel.x
	player.velocity.z = h_vel.z

	# Bullet time: right_click en aire post-hook activa camara lenta
	if _from_hook and not _bullet_time_active and Input.is_action_just_pressed("right_click"):
		_bullet_time_active = true
		_bullet_time_timer = BULLET_TIME_DURATION
		Engine.time_scale = BULLET_TIME_SCALE
	# Desactivar bullet time al soltar right_click, disparar hook, o agotar timer
	if _bullet_time_active:
		_bullet_time_timer -= delta / Engine.time_scale  # Timer en tiempo real
		player.bullet_time_ratio = clampf(_bullet_time_timer / BULLET_TIME_DURATION, 0.0, 1.0)
		if Input.is_action_just_released("right_click") or _bullet_time_timer <= 0.0:
			_end_bullet_time()

	# Gravedad: floaty post-hook o normal
	if _hook_floaty_timer > 0.0:
		_hook_floaty_timer -= delta
		# Gravedad reducida: 60% de la normal
		var grav = player._gravity * HOOK_FLOATY_GRAVITY
		if player.velocity.y < 0.0:
			grav *= player.fall_gravity_multiplier
		player.velocity.y += grav * delta
	else:
		player.apply_gravity(delta)

	# Mover
	player._pre_move_y_velocity = player.velocity.y
	player.move_and_slide()
	player.rotate_skin(delta)

	# Animaciones aereas
	if player.velocity.y < 0.0:
		player._skin.fall()

	# Deteccion de cornisa (solo al caer, antes del check de aterrizaje)
	if _check_ledge_grab():
		return

	# Aterrizaje
	if player.is_on_floor():
		_land()


func _land():
	var h_speed = Vector2(player.velocity.x, player.velocity.z).length()

	# Transferencia de momentum en rampas al aterrizar
	# Si el suelo es diagonal, convertir parte de la velocidad vertical a horizontal
	if player.is_on_floor():
		var floor_normal = player.get_floor_normal()
		if floor_normal.y < 0.95:  # Superficie diagonal
			var fall_speed = abs(player._pre_move_y_velocity)
			var slope_factor = 1.0 - floor_normal.y  # Mas empinada = mas transferencia
			var transfer = fall_speed * slope_factor * 0.5
			var h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
			var slide_dir = Vector3(floor_normal.x, 0.0, floor_normal.z).normalized()
			if h_vel.length() > 0.1:
				slide_dir = h_vel.normalized()
			h_vel += slide_dir * transfer
			player.velocity.x = h_vel.x
			player.velocity.z = h_vel.z
			h_speed = Vector2(player.velocity.x, player.velocity.z).length()

	# Slide-on-land: si crouch presionado y hay velocidad, entrar directo a Slide
	# No aplica si fue fast drop (el crouch fue para caer rapido, no para agacharse)
	# Desde slide jump: ctrl → slide encadenado (sin slide jump disponible)
	# Slide-on-land: si crouch esta mantenido (se puede presionar en el aire antes de aterrizar)
	# Bloqueado si ya se hizo el maximo de slides encadenados
	var can_slide_on_land = not _did_fast_drop and Input.is_action_pressed("crouch") and h_speed > player.slide_min_speed and _chain_count <= SlideState.MAX_EXTRA_SLIDES
	if can_slide_on_land:
		player.apply_squash_and_stretch(Vector3(1.3, 0.7, 1.3))
		player._skin.land(abs(player._pre_move_y_velocity))
		player.velocity.y = 0.0  # Solo quitar velocidad vertical
		state_machine.transition_to("Slide", {"chain_count": _chain_count})
		return

	# Aterrizaje normal: squash visual y resetear velocidad
	player.apply_squash_and_stretch(Vector3(1.3, 0.7, 1.3))
	player._skin.land(abs(player._pre_move_y_velocity))
	player.velocity = Vector3.ZERO

	# Transicionar al estado de suelo segun input actual
	var move_dir = player.get_move_direction()
	if move_dir.length() > 0.1:
		if Input.is_action_pressed("sprint"):
			state_machine.transition_to("Run")
		else:
			state_machine.transition_to("Walk")
	elif not _did_fast_drop and Input.is_action_pressed("crouch"):
		state_machine.transition_to("Crouch")
	else:
		state_machine.transition_to("Idle")


## Detecta cornisas agarrables usando 3 raycasts desde la direccion del skin.
## Solo funciona al caer y si no esta activo el anti re-grab timer.
func _check_ledge_grab() -> bool:
	# Solo al caer
	if player.velocity.y > -LEDGE_MIN_FALL_SPEED:
		return false
	# Anti re-grab
	if _skip_ledge_grab:
		return false

	var space = player.get_world_3d().direct_space_state
	var forward = player._skin.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.1:
		return false
	forward = forward.normalized()
	var origin = player.global_position

	# 1) Chest ray: detecta pared
	var chest_from = origin + Vector3.UP * LEDGE_CHEST_HEIGHT
	var chest_to = chest_from + forward * LEDGE_RAY_LENGTH
	var query = PhysicsRayQueryParameters3D.create(chest_from, chest_to)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1  # Solo layer 1 (world), NO jump-thru
	var chest_result = space.intersect_ray(query)
	if chest_result.is_empty():
		return false

	# 2) Head ray: si hay pared, la pared sigue arriba → no es cornisa
	var head_from = origin + Vector3.UP * LEDGE_HEAD_HEIGHT
	var head_to = head_from + forward * LEDGE_RAY_LENGTH
	query = PhysicsRayQueryParameters3D.create(head_from, head_to)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	var head_result = space.intersect_ray(query)
	if not head_result.is_empty():
		return false

	# 3) Down ray: desde arriba del hit, ligeramente dentro de la plataforma, hacia abajo
	#    para encontrar la superficie exacta de la cornisa
	var wall_normal = chest_result.normal
	var wall_point = chest_result.position
	var down_origin = Vector3(
		wall_point.x - wall_normal.x * 0.1,
		origin.y + LEDGE_HEAD_HEIGHT,
		wall_point.z - wall_normal.z * 0.1
	)
	var down_end = down_origin + Vector3.DOWN * 2.0
	query = PhysicsRayQueryParameters3D.create(down_origin, down_end)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	var down_result = space.intersect_ray(query)
	if down_result.is_empty():
		return false

	# Verificar que la superficie es aproximadamente horizontal
	if down_result.normal.y < 0.7:
		return false

	# Cornisa valida → transicionar
	state_machine.transition_to("LedgeGrab", {
		"wall_normal": wall_normal,
		"ledge_surface_y": down_result.position.y,
		"wall_point": wall_point
	})
	return true


func _end_bullet_time():
	if _bullet_time_active:
		_bullet_time_active = false
		Engine.time_scale = 1.0
		player.bullet_time_ratio = 0.0
