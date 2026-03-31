class_name IdleState extends State

## Estado de reposo. Friccion alta para frenar rapido.
## Transiciona a Walk, Run, Airborne o Crouch segun input.

const FRICTION := 25.0

var player: CharacterBody3D


func enter(_params := {}):
	if not player:
		player = state_machine.get_parent()
	player._target_camera_distance = player.camera_default_distance
	player._target_camera_fov = player.camera_default_fov
	if not player._skin.is_landing:
		player._skin.idle()


func process_physics(delta: float):
	# Dash cancela el punch
	if player.is_punching and Abilities.run_unlocked and Input.is_action_just_pressed("sprint"):
		player.cancel_arm_action()
		var move_dir = player.get_move_direction()
		if move_dir.length() > 0.1:
			state_machine.transition_to("Run", {"dash": true})
		else:
			_perform_dash_only()
		return

	# Bloqueo durante animacion de aterrizaje o punch
	if player._skin.is_landing or player.is_punching:
		player.velocity.x = move_toward(player.velocity.x, 0.0, 25.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 25.0 * delta)
		player.apply_gravity(delta)
		player.move_and_slide()
		return

	# Coyote timer: siempre al maximo mientras estamos en el suelo
	player.coyote_timer = player.coyote_duration

	# Friccion alta para frenar rapido
	var h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
	h_vel = h_vel.move_toward(Vector3.ZERO, FRICTION * delta)
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

	# Mover
	player._pre_move_y_velocity = player.velocity.y
	player.move_and_slide()
	player.rotate_skin(delta)

	# Transiciones
	if not player.is_on_floor():
		state_machine.transition_to("Airborne")
		return

	if Input.is_action_pressed("crouch"):
		state_machine.transition_to("Crouch")
		return

	# Aim mode: right click mantenido
	if Input.is_action_pressed("right_click"):
		state_machine.transition_to("Aim")
		return

	var move_dir = player.get_move_direction()

	if Abilities.run_unlocked and Input.is_action_just_pressed("sprint"):
		if move_dir.length() > 0.1:
			# Sprint con direccion: entrar a Run (con dash boost)
			state_machine.transition_to("Run", {"dash": true})
		else:
			# Sprint sin direccion: solo dash, quedarse en Idle
			_perform_dash_only()
		return

	if move_dir.length() > 0.1:
		if Abilities.run_unlocked and Input.is_action_pressed("sprint"):
			state_machine.transition_to("Run")
		else:
			state_machine.transition_to("Walk")
		return

	# Animacion
	player._skin.idle()


## Dash sin movimiento: impulso en la direccion de la camara, sin entrar a Run.
func _perform_dash_only():
	if not Abilities.dash_unlocked or player.dash_cooldown > 0.0:
		return
	player.cancel_arm_action()
	var dash_dir = player._skin.global_basis.z
	dash_dir.y = 0.0
	dash_dir = dash_dir.normalized()
	var h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var boosted_speed = max(h_vel.length() * 2.0, 22.0)
	h_vel = dash_dir * boosted_speed
	player.velocity.x = h_vel.x
	player.velocity.z = h_vel.z
	player.dash_cooldown = 1.5
	player._skin.jump()
