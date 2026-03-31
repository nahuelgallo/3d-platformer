class_name FistArm extends ArmBase

# Brazo base: punos. Golpe simple con deteccion via raycast.
# El golpe tiene prioridad: bloquea hasta que termina la animacion.
# El cooldown empieza DESPUES de que termina el golpe.
# Se puede cancelar con dash/slide.

const PUNCH_COOLDOWN := 0.4
const PUNCH_RANGE := 2.0
const PUNCH_DURATION := 0.4

var _cooldown_timer := 0.0
var _punch_timer := 0.0
var _is_punching := false


func _physics_process(delta):
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if _is_punching:
		_punch_timer -= delta
		if _punch_timer <= 0.0:
			_is_punching = false
			_cooldown_timer = PUNCH_COOLDOWN


func primary_action() -> void:
	if _cooldown_timer > 0.0 or _is_punching:
		return
	_is_punching = true
	_punch_timer = PUNCH_DURATION

	# Animacion de golpe
	if player:
		player._skin.punch()

	# Deteccion de golpe via raycast
	_detect_hit()


## Cancelar el golpe externamente (ej: dash, slide)
func cancel_punch() -> void:
	_is_punching = false
	_punch_timer = 0.0
	_cooldown_timer = 0.0
	if player:
		player._skin.cancel_punch()


func _detect_hit():
	if not player:
		return
	var space = player.get_world_3d().direct_space_state
	var from = player.global_position + Vector3.UP * 0.8
	var forward = -player._skin.global_basis.z
	var to = from + forward * PUNCH_RANGE
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var result = space.intersect_ray(query)
	if result:
		print("FistArm: Hit %s" % result.collider.name)
