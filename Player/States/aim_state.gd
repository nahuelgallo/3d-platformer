class_name AimState extends State

## Estado de apuntado (mira). Activado con right click (hold).
## Camara hace zoom, personaje mira hacia la camara, movimiento strafe.
## Prohibido: dash, crouch, slide. Permitido: saltar, golpear.

const FRICTION := 19.0
const ACCELERATION := 20.0
const BULLET_TIME_SCALE := 0.25   # Misma escala que airborne bullet time
const BULLET_TIME_DURATION := 1.5 # Duracion maxima del bullet time

var player: CharacterBody3D
var _bullet_time_active := false
var _bullet_time_timer := 0.0


func enter(_params := {}):
	if not player:
		player = state_machine.get_parent()
	player._target_camera_distance = player.camera_aim_distance
	player._target_camera_fov = player.camera_aim_fov
	Events.aim_started.emit()
	# Activar bullet time al entrar en aim
	_bullet_time_active = true
	_bullet_time_timer = BULLET_TIME_DURATION
	Engine.time_scale = BULLET_TIME_SCALE
	# Animacion segun input actual
	_update_animation()


func exit():
	_end_bullet_time()
	Events.aim_ended.emit()


func process_physics(delta: float):
	# Bullet time timer (cuenta en tiempo real, no escalado)
	if _bullet_time_active:
		_bullet_time_timer -= delta / Engine.time_scale
		player.bullet_time_ratio = clampf(_bullet_time_timer / BULLET_TIME_DURATION, 0.0, 1.0)
		if _bullet_time_timer <= 0.0:
			_end_bullet_time()

	# Bloqueo durante animacion de aterrizaje o punch
	if player._skin.is_landing or player.is_punching:
		player.velocity.x = move_toward(player.velocity.x, 0.0, 25.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 25.0 * delta)
		player.apply_gravity(delta)
		player.move_and_slide()
		return

	# Coyote timer
	player.coyote_timer = player.coyote_duration

	# --- ROTACION: skin mira hacia donde apunta la camara ---
	var cam_forward = -player._camera.global_basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	if cam_forward.length() > 0.1:
		var target_angle = Vector3.BACK.signed_angle_to(cam_forward, Vector3.UP)
		player._skin.global_rotation.y = lerp_angle(
			player._skin.global_rotation.y, target_angle, player.rotation_speed * delta
		)

	# --- MOVIMIENTO: velocidad reducida, strafe ---
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

	# Mover (sin rotate_skin - la rotacion la manejamos arriba)
	player._pre_move_y_velocity = player.velocity.y
	player.move_and_slide()

	# --- TRANSICIONES ---
	if not player.is_on_floor():
		state_machine.transition_to("Airborne")
		return

	# Soltar right click: volver al estado de suelo apropiado
	if not Input.is_action_pressed("right_click"):
		var h_speed = Vector2(player.velocity.x, player.velocity.z).length()
		if h_speed > 0.5:
			if Abilities.run_unlocked and Input.is_action_pressed("sprint"):
				state_machine.transition_to("Run")
			else:
				state_machine.transition_to("Walk")
		else:
			state_machine.transition_to("Idle")
		return

	# Animaciones strafe
	_update_animation()


func _end_bullet_time():
	if _bullet_time_active:
		_bullet_time_active = false
		Engine.time_scale = 1.0
		player.bullet_time_ratio = 0.0


## Determina que animacion reproducir segun el input relativo a la camara.
func _update_animation():
	var raw_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if raw_input.length() < 0.1:
		player._skin.idle()
		return

	# Input lateral dominante → strafe
	if abs(raw_input.x) > abs(raw_input.y):
		if raw_input.x < 0.0:
			player._skin.strafe_left()
		else:
			player._skin.strafe_right()
	else:
		# Input frontal/trasero → walk normal
		player._skin.move()
