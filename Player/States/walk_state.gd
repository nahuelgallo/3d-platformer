class_name WalkState extends State

## Estado de caminata. Movimiento con move_speed y aceleracion normal.
## Transiciona a Idle, Run, Airborne o Crouch segun input.

const FRICTION := 19.0
const ACCELERATION := 20.0

var player: CharacterBody3D


func enter(_params := {}):
	if not player:
		player = state_machine.get_parent()
	player._target_camera_distance = player.camera_default_distance
	player._target_camera_fov = player.camera_default_fov
	player._skin.move()


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
	if move_dir.length() > 0.1:
		h_vel = h_vel.move_toward(move_dir * player.move_speed, ACCELERATION * delta)
	else:
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

	# Mover (con step-up para micro-escalones)
	player._pre_move_y_velocity = player.velocity.y
	player.move_with_step_up()
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

	if Abilities.run_unlocked and Input.is_action_pressed("sprint"):
		if Input.is_action_just_pressed("sprint"):
			state_machine.transition_to("Run", {"dash": true})
		else:
			state_machine.transition_to("Run")
		return

	var h_speed = Vector2(player.velocity.x, player.velocity.z).length()
	if move_dir.length() < 0.1 and h_speed < 0.5:
		state_machine.transition_to("Idle")
		return

	# Animacion
	player._skin.move()
