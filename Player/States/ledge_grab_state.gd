class_name LedgeGrabState extends State

## Estado de agarrar cornisa. El jugador cuelga del borde de una plataforma.
## Shimmy (A/D relativo a camara), subir (Space), soltar (Ctrl).
## Hook funciona automaticamente via _unhandled_input del player.

const SHIMMY_SPEED := 2.5
const SNAP_OFFSET := 0.35       # Distancia del player a la pared
const CLIMB_FORWARD_OFFSET := 0.8  # Cuanto avanza al subir
const PLAYER_HEIGHT := 2.3      # Distancia del origen (pies) a las manos
const CHEST_HEIGHT := 1.5
const HEAD_HEIGHT := 2.4
const RAY_LENGTH := 0.7

var player: CharacterBody3D
var _wall_normal := Vector3.ZERO
var _ledge_surface_y := 0.0
var _wall_point := Vector3.ZERO
var _wall_right := Vector3.ZERO  # Direccion lateral a lo largo de la pared


func enter(params := {}):
	if not player:
		player = state_machine.get_parent()

	_wall_normal = params.get("wall_normal", Vector3.ZERO)
	_ledge_surface_y = params.get("ledge_surface_y", 0.0)
	_wall_point = params.get("wall_point", Vector3.ZERO)
	_wall_right = Vector3.UP.cross(_wall_normal).normalized()

	# Snap Y: manos a la altura de la cornisa
	player.global_position.y = _ledge_surface_y - PLAYER_HEIGHT
	# Snap X/Z: contra la pared
	var snap_pos = _wall_point + _wall_normal * SNAP_OFFSET
	player.global_position.x = snap_pos.x
	player.global_position.z = snap_pos.z

	player.velocity = Vector3.ZERO
	player.set_crouching(false)

	# Rotar skin para mirar la pared (inmediato)
	var look_dir = -_wall_normal
	look_dir.y = 0.0
	if look_dir.length() > 0.1:
		var angle = Vector3.BACK.signed_angle_to(look_dir.normalized(), Vector3.UP)
		player._skin.global_rotation.y = angle

	# Animacion de colgado
	player._skin.fall()

	# Camara default
	player._target_camera_distance = player.camera_default_distance
	player._target_camera_fov = player.camera_default_fov


func process_physics(delta: float):
	# Sin gravedad, mantener posicion Y
	player.velocity = Vector3.ZERO
	player.global_position.y = _ledge_surface_y - PLAYER_HEIGHT

	# --- SUBIR (Space) ---
	if Input.is_action_just_pressed("jump"):
		var forward = -_wall_normal
		forward.y = 0.0
		forward = forward.normalized()
		player.global_position = Vector3(
			player.global_position.x + forward.x * CLIMB_FORWARD_OFFSET,
			_ledge_surface_y + 0.1,
			player.global_position.z + forward.z * CLIMB_FORWARD_OFFSET
		)
		player.velocity = Vector3.ZERO
		state_machine.transition_to("Idle")
		return

	# --- SOLTAR (Ctrl) ---
	if Input.is_action_just_pressed("crouch"):
		state_machine.transition_to("Airborne", {"skip_ledge_grab": true})
		return

	# --- SHIMMY (A/D relativo a camara, proyectado sobre la pared) ---
	var move_dir = player.get_move_direction()
	var lateral = move_dir.dot(_wall_right)
	if abs(lateral) > 0.1:
		var old_pos = player.global_position
		player.global_position += _wall_right * lateral * SHIMMY_SPEED * delta

		# Validar que sigue habiendo cornisa; si no, restaurar y soltar
		if not _validate_and_snap():
			player.global_position = old_pos
			state_machine.transition_to("Airborne", {"skip_ledge_grab": true})
			return

	# Skin mira la pared (lerp suave, util si wall_normal cambia en curvas)
	var look_dir = -_wall_normal
	look_dir.y = 0.0
	if look_dir.length() > 0.1:
		var target_angle = Vector3.BACK.signed_angle_to(look_dir.normalized(), Vector3.UP)
		player._skin.global_rotation.y = lerp_angle(
			player._skin.global_rotation.y, target_angle, 10.0 * delta
		)


## Valida que en la posicion actual sigue habiendo cornisa agarrable.
## Si es valida, re-snappea X/Z contra la pared y actualiza wall_normal.
func _validate_and_snap() -> bool:
	var space = player.get_world_3d().direct_space_state
	var forward = -_wall_normal
	forward.y = 0.0
	forward = forward.normalized()
	var origin = player.global_position

	# Chest ray: debe haber pared
	var chest_from = origin + Vector3.UP * CHEST_HEIGHT
	var chest_to = chest_from + forward * RAY_LENGTH
	var query = PhysicsRayQueryParameters3D.create(chest_from, chest_to)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1  # Solo layer 1 (world)
	var result = space.intersect_ray(query)
	if result.is_empty():
		return false

	# Actualizar datos de pared desde el nuevo hit
	_wall_normal = result.normal
	_wall_point = result.position
	_wall_right = Vector3.UP.cross(_wall_normal).normalized()

	# Re-snap X/Z contra la pared
	var snap_pos = _wall_point + _wall_normal * SNAP_OFFSET
	player.global_position.x = snap_pos.x
	player.global_position.z = snap_pos.z

	# Head ray: NO debe haber pared (confirma que es cornisa, no pared alta)
	forward = -_wall_normal
	forward.y = 0.0
	forward = forward.normalized()
	var head_from = origin + Vector3.UP * HEAD_HEIGHT
	var head_to = head_from + forward * RAY_LENGTH
	query = PhysicsRayQueryParameters3D.create(head_from, head_to)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	result = space.intersect_ray(query)
	return result.is_empty()
