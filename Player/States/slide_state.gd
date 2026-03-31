class_name SlideState extends State

## Estado de deslizamiento. Friccion muy baja, sin aceleracion manual.
## El jugador se desliza con momentum, girando suavemente.
## Sale a Crouch cuando la velocidad baja del umbral, Airborne si cae.

const FRICTION_MIN := 3.0   # Friccion a velocidad alta (desliza libre)
const FRICTION_MAX := 15.0  # Friccion a velocidad baja (frenazo al final)
const FRICTION_RAMP_SPEED := 10.0  # Por encima de esta velocidad, friccion es minima
const CHAIN_FRICTION := 19.0  # Friccion del slide encadenado (igual a caminata)
const MAX_EXTRA_SLIDES := 1  # Slides extra permitidos despues del primer slide jump
const TURN_SPEED := 5.06  # Velocidad de giro suave durante el slide
const STEER_STRENGTH := 13.5  # Fuerza de viraje lateral durante slide
const SLIDE_JUMP_H_BOOST := 1.35  # +35% velocidad horizontal al saltar desde slide
const SLIDE_JUMP_V_BOOST := 1.10  # +10% altura extra al saltar desde slide
const SLIDE_JUMP_MAX_H_SPEED := 20.0  # Tope de velocidad horizontal del slide jump

const SLIDE_DURATION := 0.8  # Duracion maxima del slide (coincide con animacion: 24 frames a 30fps)

var player: CharacterBody3D
var _skip_exit_collider := false
var _chain_count := 0  # Cantidad de slides encadenados desde slide jump (max 1 extra)
var _slide_timer := 0.0


func enter(_params := {}):
	if not player:
		player = state_machine.get_parent()
	_skip_exit_collider = false
	_chain_count = _params.get("chain_count", 0)
	_slide_timer = SLIDE_DURATION

	# Activar collider reducido y cooldown
	player.set_crouching(true)
	player.slide_cooldown = 2.0

	# Boost de velocidad al entrar en slide (capeado para evitar acumulacion)
	var h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if h_vel.length() > 0.1:
		h_vel *= player.slide_boost
		if h_vel.length() > SLIDE_JUMP_MAX_H_SPEED:
			h_vel = h_vel.normalized() * SLIDE_JUMP_MAX_H_SPEED
		player.velocity.x = h_vel.x
		player.velocity.z = h_vel.z

	player._target_camera_distance = player.camera_sprint_distance
	player._target_camera_fov = player.camera_sprint_fov
	player._skin.slide()


func exit():
	# Restaurar collider normal (salvo si el slide jump ya lo hizo)
	if not _skip_exit_collider:
		player.set_crouching(false)
		# Reducir velocidad al salir del slide (no aplica a slide jump)
		var h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
		h_vel *= 0.3
		player.velocity.x = h_vel.x
		player.velocity.z = h_vel.z


func process_physics(delta: float):
	# Coyote timer: siempre al maximo mientras estamos en el suelo
	player.coyote_timer = player.coyote_duration

	# Steering lateral: el jugador puede virar suavemente sin acelerar
	var h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var move_dir = player.get_move_direction()
	if move_dir.length() > 0.1 and h_vel.length() > 0.5:
		# Solo aplicar la componente perpendicular a la velocidad (viraje, no aceleracion)
		var slide_forward = h_vel.normalized()
		var lateral = move_dir - slide_forward * move_dir.dot(slide_forward)
		h_vel += lateral * STEER_STRENGTH * delta

	# Transferencia de momentum en rampas
	if player.is_on_floor():
		var floor_normal = player.get_floor_normal()
		if floor_normal.y < 0.99:  # Superficie no plana (rampa)
			# Proyectar la gravedad sobre la pendiente del suelo
			var slide_dir = h_vel.normalized()
			var gravity_along_slope = -player._gravity * (1.0 - floor_normal.y) * delta
			# Si bajamos la rampa (slide_dir apunta "cuesta abajo"), acelerar
			# Si subimos, frenar
			var slope_direction = Vector3(floor_normal.x, 0.0, floor_normal.z).normalized()
			var alignment = slide_dir.dot(slope_direction)
			h_vel += slide_dir * gravity_along_slope * alignment

	# Friccion: curva cuadratica para slide normal, friccion de caminata para encadenado
	var friction: float
	if _chain_count > 0:
		friction = CHAIN_FRICTION
	else:
		var h_speed_for_friction = h_vel.length()
		var t = clamp((h_speed_for_friction - player.slide_min_speed) / (FRICTION_RAMP_SPEED - player.slide_min_speed), 0.0, 1.0)
		friction = lerp(FRICTION_MAX, FRICTION_MIN, t * t)
	h_vel = h_vel.move_toward(Vector3.ZERO, friction * delta)
	player.velocity.x = h_vel.x
	player.velocity.z = h_vel.z

	# Gravedad
	player.apply_gravity(delta)

	# Mover
	player._pre_move_y_velocity = player.velocity.y
	player.move_and_slide()

	# Rotar skin suavemente en la direccion del slide
	var current_h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if current_h_vel.length() > 0.5:
		var target_angle = Vector3.BACK.signed_angle_to(current_h_vel.normalized(), Vector3.UP)
		player._skin.global_rotation.y = lerp_angle(
			player._skin.global_rotation.y, target_angle, TURN_SPEED * delta
		)

	# Slide jump: solo disponible en el slide inicial (chain_count == 0)
	if player.jump_buffer_timer > 0.0 and _chain_count < MAX_EXTRA_SLIDES:
		var jump_h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
		jump_h_vel *= SLIDE_JUMP_H_BOOST
		# Capear velocidad horizontal para evitar acumulacion infinita
		if jump_h_vel.length() > SLIDE_JUMP_MAX_H_SPEED:
			jump_h_vel = jump_h_vel.normalized() * SLIDE_JUMP_MAX_H_SPEED
		player.velocity.x = jump_h_vel.x
		player.velocity.z = jump_h_vel.z
		player.velocity.y = player.jump_impulse * SLIDE_JUMP_V_BOOST
		player.jump_buffer_timer = 0.0
		player.coyote_timer = 0.0
		player.set_crouching(false)
		player.move_and_slide()
		player.apply_squash_and_stretch(Vector3(0.6, 1.5, 0.6))
		player._skin.jump()
		_skip_exit_collider = true
		state_machine.transition_to("Airborne", {"jumped": true, "boosted": true, "from_slide_jump": true, "chain_count": _chain_count + 1})
		return

	# Salto normal desde slide (cuando ya no puede hacer slide jump)
	if player.jump_buffer_timer > 0.0 and _chain_count >= MAX_EXTRA_SLIDES:
		player.velocity.y = player.jump_impulse
		player.jump_buffer_timer = 0.0
		player.coyote_timer = 0.0
		player.set_crouching(false)
		player.move_and_slide()
		player.apply_squash_and_stretch(Vector3(0.7, 1.4, 0.7))
		player._skin.jump()
		_skip_exit_collider = true
		state_machine.transition_to("Airborne", {"jumped": true, "chain_count": _chain_count + 1})
		return

	# Caer del borde
	if not player.is_on_floor():
		state_machine.transition_to("Airborne", {"chain_count": _chain_count})
		return

	# Cancelar slide con crouch (press de nuevo)
	if Input.is_action_just_pressed("crouch"):
		if player.can_stand_up():
			state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Crouch")
		return

	# Cancelar slide con sprint → entra a Run (con dash boost)
	if Input.is_action_just_pressed("sprint"):
		if player.can_stand_up():
			state_machine.transition_to("Run", {"dash": true})
			return

	# Timer del slide: termina cuando se acaba la animacion o la velocidad es baja
	_slide_timer -= delta
	var h_speed = Vector2(player.velocity.x, player.velocity.z).length()
	if _slide_timer <= 0.0 or h_speed < player.slide_min_speed:
		if player.can_stand_up():
			state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Crouch")
		return

	# Animacion
	player._skin.slide()
