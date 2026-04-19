class_name RunState extends State

## Estado de sprint. Velocidad alta con aceleracion alta.
## Transiciona a Walk, Idle, Airborne o Crouch segun input.

const FRICTION_MIN := 3.9   # Friccion cuando la velocidad es alta (post-boost)
const FRICTION_MAX := 18.2  # Friccion normal de sprint
const FRICTION_RAMP_SPEED := 12.0  # Por encima de esta velocidad, friccion es minima
const ACCELERATION := 25.0
const DASH_BOOST := 2.5  # Multiplicador de velocidad al entrar en sprint
const DASH_MIN_SPEED := 27.0  # Velocidad minima garantizada del dash
const DASH_COOLDOWN := 1.084  # Segundos entre dashes

var player: CharacterBody3D


func enter(_params := {}):
	if not player:
		player = state_machine.get_parent()

	# Cancelar punch si estaba golpeando
	player.cancel_arm_action()

	# Dash boost: solo si se pidio explicitamente (no en cada re-entrada a Run)
	var attempt_dash = _params.get("dash", false)
	if attempt_dash and Abilities.dash_unlocked and Stamina.try_consume(0.5):
		var move_dir = player.get_move_direction()
		# Si no hay input de movimiento, usar la direccion donde mira el modelo
		if move_dir.length() < 0.1:
			move_dir = player._skin.global_basis.z
			move_dir.y = 0.0
			move_dir = move_dir.normalized()
		var h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
		var boosted_speed = clamp(max(h_vel.length() * DASH_BOOST, DASH_MIN_SPEED), 0.0, DASH_MIN_SPEED)
		h_vel = move_dir * boosted_speed
		player.velocity.x = h_vel.x
		player.velocity.z = h_vel.z
		player._skin.jump()

	player._target_camera_distance = player.camera_sprint_distance
	player._target_camera_fov = player.camera_sprint_fov
	player._skin.run()


func process_physics(delta: float):
	# Dash cancela el punch
	if player.is_punching and Abilities.run_unlocked and Input.is_action_just_pressed("sprint"):
		player.cancel_arm_action()
		state_machine.transition_to("Run", {"dash": true})
		return

	# Bloqueo durante animacion de aterrizaje o punch
	if player._skin.is_landing or player.is_punching:
		player.velocity.x = move_toward(player.velocity.x, 0.0, 25.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 25.0 * delta)
		player.apply_gravity(delta)
		player.move_and_slide()
		return

	# Coyote timer
	player.coyote_timer = player.coyote_duration

	# Movimiento horizontal
	var move_dir = player.get_move_direction()
	var h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
	# Friccion con curva cuadratica: baja post-boost, frenazo al acercarse a sprint_speed
	var h_speed_now = h_vel.length()
	var t = clamp((h_speed_now - player.sprint_speed) / (FRICTION_RAMP_SPEED - player.sprint_speed), 0.0, 1.0)
	var friction = lerp(FRICTION_MAX, FRICTION_MIN, t * t)
	if move_dir.length() > 0.1:
		h_vel = h_vel.move_toward(move_dir * player.sprint_speed, ACCELERATION * delta)
	else:
		h_vel = h_vel.move_toward(Vector3.ZERO, friction * delta)
	player.velocity.x = h_vel.x
	player.velocity.z = h_vel.z

	# Gravedad
	player.apply_gravity(delta)

	# Salto
	if player.jump_buffer_timer > 0.0:
		player.perform_jump()
		player._pre_move_y_velocity = player.velocity.y
		player.move_and_slide()
		state_machine.transition_to("Airborne", {"jumped": true})
		return

	# Mover (con step-up para micro-escalones)
	player._pre_move_y_velocity = player.velocity.y
	player.move_with_step_up()
	player.rotate_skin(delta)

	# Transiciones
	if not player.is_on_floor():
		state_machine.transition_to("Airborne")
		return

	if Input.is_action_just_pressed("crouch"):
		var h_speed_crouch = Vector2(player.velocity.x, player.velocity.z).length()
		if Abilities.slide_unlocked and h_speed_crouch > player.slide_min_speed and player.slide_cooldown <= 0.0:
			state_machine.transition_to("Slide")
		else:
			state_machine.transition_to("Crouch")
		return

	# Aim mode: right click mantenido
	if Input.is_action_pressed("right_click"):
		state_machine.transition_to("Aim")
		return

	if not Input.is_action_pressed("sprint"):
		state_machine.transition_to("Walk")
		return

	var move_dir_check = player.get_move_direction()
	# Sin input de direccion: no quedarse corriendo, volver a Idle
	if move_dir_check.length() < 0.1:
		state_machine.transition_to("Idle")
		return

	# Animacion
	player._skin.run()
