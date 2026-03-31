class_name HookedState extends State

## Estado enganchado al grappling hook. El jugador cuelga como pendulo.
## Gravedad + control aereo minimo + constraint de cuerda.
## Sale con: salto (impulso), left click (recoil hacia attach point), tocar suelo (automatico).

const AIR_CONTROL := 3.0
const RELEASE_JUMP_MULT := 0.7  # Porcentaje del impulso de salto al soltar con jump
const RECOIL_SPEED := 25.0  # Velocidad de lanzamiento hacia el punto de enganche
const HOOKED_FOV := 85.0
const CLIMB_SPEED := 5.0  # Velocidad de subir/bajar la cuerda
const MIN_ROPE_LENGTH := 1.5  # Largo minimo de la cuerda

var player: CharacterBody3D
var _attach_point := Vector3.ZERO
var _rope_length := 0.0


func enter(params := {}):
	if not player:
		player = state_machine.get_parent()
	_attach_point = params.get("attach_point", Vector3.ZERO)
	_rope_length = params.get("rope_length", 5.0)

	# Camara
	player._target_camera_distance = player.camera_sprint_distance
	player._target_camera_fov = HOOKED_FOV

	# Animacion de caida/colgado
	player._skin.fall()


func exit():
	player._target_camera_distance = player.camera_default_distance
	player._target_camera_fov = player.camera_default_fov


func process_physics(delta: float):
	# Gravedad
	player.apply_gravity(delta)

	# Subir/bajar cuerda: shift acorta, ctrl alarga
	if Input.is_action_pressed("sprint"):
		_rope_length = max(_rope_length - CLIMB_SPEED * delta, MIN_ROPE_LENGTH)
	elif Input.is_action_pressed("crouch"):
		_rope_length += CLIMB_SPEED * delta

	# Control aereo minimo para influir en el pendulo
	var move_dir = player.get_move_direction()
	if move_dir.length() > 0.1:
		player.velocity.x += move_dir.x * AIR_CONTROL * delta
		player.velocity.z += move_dir.z * AIR_CONTROL * delta

	# Mover primero para que move_and_slide resuelva colisiones
	player.move_and_slide()

	# Constraint de cuerda: si el player se aleja mas que rope_length, clampearlo
	var to_player = player.global_position - _attach_point
	var distance = to_player.length()
	if distance > _rope_length:
		# Clampear posicion al radio de la cuerda
		var clamped_pos = _attach_point + to_player.normalized() * _rope_length
		player.global_position = clamped_pos

		# Quitar componente radial saliente de la velocidad
		# (solo permite velocidad tangencial o hacia el centro)
		var radial_dir = to_player.normalized()
		var radial_vel = player.velocity.dot(radial_dir)
		if radial_vel > 0.0:
			player.velocity -= radial_dir * radial_vel

	# Rotar skin hacia direccion de movimiento
	player.rotate_skin(delta)

	# --- TRANSICIONES ---

	# Recoil: left click lanza al jugador hacia el punto de enganche
	if Input.is_action_just_pressed("left_click"):
		var recoil_dir = (_attach_point - player.global_position).normalized()
		player.velocity = recoil_dir * RECOIL_SPEED
		_notify_arm_release()
		state_machine.transition_to("Airborne", {"jumped": true, "boosted": true, "from_hook": true})
		return

	# Soltar con salto: impulso
	if player.jump_buffer_timer > 0.0:
		player.jump_buffer_timer = 0.0
		player.velocity.y += player.jump_impulse * RELEASE_JUMP_MULT
		_notify_arm_release()
		state_machine.transition_to("Airborne", {"jumped": true, "from_hook": true})
		return

	# Tocar suelo: release automatico
	if player.is_on_floor():
		_notify_arm_release()
		var h_speed = Vector2(player.velocity.x, player.velocity.z).length()
		if h_speed > 0.5:
			state_machine.transition_to("Walk")
		else:
			state_machine.transition_to("Idle")
		return


## Notifica al brazo que se solto el gancho (via has_method para desacople)
func _notify_arm_release():
	if player._arm_socket and player._arm_socket.current_arm:
		var arm = player._arm_socket.current_arm
		if arm.has_method("cancel_hook"):
			arm.cancel_hook()
