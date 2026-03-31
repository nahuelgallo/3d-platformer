class_name CrouchState extends State

## Estado agachado. Velocidad reducida, collider reducido, no puede saltar.
## Transiciona a Slide si tiene velocidad al entrar, Idle/Walk al soltar crouch,
## Airborne si cae. Verifica techo antes de pararse.

const FRICTION := 20.0
const ACCELERATION := 15.0

var player: CharacterBody3D


func enter(_params := {}):
	if not player:
		player = state_machine.get_parent()

	player._target_camera_distance = player.camera_default_distance
	player._target_camera_fov = player.camera_default_fov
	# Activar collider reducido
	player.set_crouching(true)
	player._skin.crouch()


func exit():
	# Restaurar collider normal
	player.set_crouching(false)


func process_physics(delta: float):
	# Bloqueo durante animacion de aterrizaje
	if player._skin.is_landing:
		player.velocity = Vector3.ZERO
		player.move_and_slide()
		return

	# Coyote timer
	player.coyote_timer = player.coyote_duration

	# Movimiento horizontal (velocidad reducida)
	var move_dir = player.get_move_direction()
	var h_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if move_dir.length() > 0.1:
		h_vel = h_vel.move_toward(move_dir * player.crouch_speed, ACCELERATION * delta)
	else:
		h_vel = h_vel.move_toward(Vector3.ZERO, FRICTION * delta)
	player.velocity.x = h_vel.x
	player.velocity.z = h_vel.z

	# Gravedad
	player.apply_gravity(delta)

	# No se puede saltar agachado

	# Mover
	player._pre_move_y_velocity = player.velocity.y
	player.move_and_slide()
	player.rotate_skin(delta)

	# Drop-through: crouch + move_down sobre una JumpThruPlatform
	if Input.is_action_pressed("move_down"):
		_try_drop_through()

	# Transiciones
	if not player.is_on_floor():
		state_machine.transition_to("Airborne")
		return

	# Hold: soltar crouch para pararse
	if not Input.is_action_pressed("crouch"):
		if not player.can_stand_up():
			# Techo encima: quedarse agachado hasta que haya espacio
			pass
		else:
			var h_speed = Vector2(player.velocity.x, player.velocity.z).length()
			if h_speed > 0.5 or move_dir.length() > 0.1:
				if Input.is_action_pressed("sprint"):
					state_machine.transition_to("Run")
				else:
					state_machine.transition_to("Walk")
			else:
				state_machine.transition_to("Idle")
			return

	# Animaciones de crouch
	var h_speed = Vector2(player.velocity.x, player.velocity.z).length()
	if h_speed > 0.5:
		player._skin.crouch_walk()
	else:
		player._skin.crouch()


## Busca si el jugador esta parado sobre una JumpThruPlatform y la atraviesa.
func _try_drop_through() -> void:
	# Revisar las colisiones del ultimo move_and_slide
	for i in player.get_slide_collision_count():
		var collision = player.get_slide_collision(i)
		var collider = collision.get_collider()
		if collider is JumpThruPlatform:
			collider.drop_through()
			return
