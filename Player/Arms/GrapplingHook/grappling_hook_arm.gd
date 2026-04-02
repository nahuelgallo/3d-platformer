class_name GrapplingHookArm extends ArmBase

# Brazo de grappling hook. Dispara un proyectil que se engancha a
# HookRings (layer 4) y JumpThruPlatforms (layer 3).
# Estados internos: IDLE, CHARGING, FLYING, ATTACHED.
# Mantener click = cargar. Soltar = disparar. Mas carga = mas distancia.

enum HookState { IDLE, CHARGING, FLYING, ATTACHED }

const HOOK_SPEED := 80.0
const HOOK_MIN_DISTANCE := 5.0   # Distancia minima (sin cargar)
const HOOK_MAX_DISTANCE := 20.0  # Distancia maxima (carga completa)
const CHARGE_TIME := 1.5         # Segundos para carga completa

var _state := HookState.IDLE
var _projectile: HookProjectile
var _rope: RopeVisual
var _attach_point := Vector3.ZERO
var _surface_normal := Vector3.DOWN  # Normal de la superficie donde se engancho
var _is_hook_ring := false           # Si se engancho a un HookRing (siempre pendulo)
var _attached_collider: Node = null
var _charge_timer := 0.0
var _current_max_distance := 0.0  # Distancia calculada segun carga


func _setup(p: CharacterBody3D) -> void:
	super._setup(p)
	# Crear hijos programaticamente
	_projectile = HookProjectile.new()
	_projectile.name = "HookProjectile"
	add_child(_projectile)
	_projectile.hit_target.connect(_on_hook_hit)
	_projectile.missed.connect(_on_hook_missed)

	_rope = RopeVisual.new()
	_rope.name = "RopeVisual"
	add_child(_rope)


func primary_action() -> void:
	match _state:
		HookState.IDLE:
			# Empezar a cargar
			_state = HookState.CHARGING
			_charge_timer = 0.0
		HookState.ATTACHED:
			pass  # Recoil/release lo maneja HookedState via left click


func release_action() -> void:
	if _state == HookState.CHARGING:
		# Soltar click = disparar con la carga acumulada
		_fire_hook()


func _fire_hook() -> void:
	if not player:
		_state = HookState.IDLE
		return

	# Calcular distancia segun carga (lerp entre min y max)
	var charge_ratio = clampf(_charge_timer / CHARGE_TIME, 0.0, 1.0)
	_current_max_distance = lerpf(HOOK_MIN_DISTANCE, HOOK_MAX_DISTANCE, charge_ratio)

	var target_point: Vector3
	var fire_distance: float
	var crosshair = _get_crosshair()

	if crosshair and crosshair.has_target:
		# Mira automatica: el hook va directo al target del crosshair
		target_point = crosshair.current_attach_point
		# Usar la distancia real al target (no la de carga) para que siempre llegue
		fire_distance = player.global_position.distance_to(target_point) + 2.0
	else:
		# Sin crosshair o sin target — raycast original
		target_point = _raycast_target_point(charge_ratio)
		fire_distance = _current_max_distance

	# Direccion del disparo: desde la mano del player hacia el target point
	var hand_pos = _get_hand_position()
	var fire_dir = (target_point - hand_pos).normalized()

	_state = HookState.FLYING
	_projectile.fire(hand_pos, fire_dir, HOOK_SPEED, fire_distance)
	Events.hook_fired.emit()
	print("GrapplingHook: disparo hacia %s (distancia: %.1f)" % [target_point, fire_distance])


## Raycast original desde centro de camara (fallback cuando no hay crosshair target)
func _raycast_target_point(charge_ratio: float) -> Vector3:
	var camera: Camera3D = player._camera
	var viewport = camera.get_viewport()
	var screen_center = viewport.get_visible_rect().size * 0.5
	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_dir = camera.project_ray_normal(screen_center)

	var space = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_dir * _current_max_distance * 2.0
	)
	query.collision_mask = 0b1001101  # layers 1, 3, 4, 7
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [player.get_rid()]

	var result = space.intersect_ray(query)
	if result:
		return result.position
	return ray_origin + ray_dir * _current_max_distance


func _on_hook_hit(hit_position: Vector3, collider: Node, hit_normal: Vector3) -> void:
	_state = HookState.ATTACHED
	_attach_point = hit_position
	_surface_normal = hit_normal
	_attached_collider = collider
	var rope_length = player.global_position.distance_to(_attach_point)

	# Detectar tipo de collider
	var flex_pole = _find_flex_pole(collider)
	_is_hook_ring = _find_hook_ring(collider)

	if flex_pole:
		Events.pole_grabbed.emit(hit_position)
		arm_state_changed.emit("FlexPoleHooked")
		print("GrapplingHook: enganchado a FlexPole en %s" % [hit_position])
	else:
		Events.hook_attached.emit(hit_position)
		arm_state_changed.emit("Hooked")
		print("GrapplingHook: enganchado en %s (ring=%s, normal: %s)" % [hit_position, _is_hook_ring, hit_normal])


## Busca si el collider o su padre es un HookRing
func _find_hook_ring(collider: Node) -> bool:
	if collider is HookRing:
		return true
	var parent = collider.get_parent()
	while parent:
		if parent is HookRing:
			return true
		parent = parent.get_parent()
	return false


func is_hook_ring() -> bool:
	return _is_hook_ring


## Busca si el collider o su padre es un FlexPole
func _find_flex_pole(collider: Node) -> FlexPole:
	if collider is FlexPole:
		return collider
	var parent = collider.get_parent()
	while parent:
		if parent is FlexPole:
			return parent
		parent = parent.get_parent()
	return null


func _on_hook_missed() -> void:
	_state = HookState.IDLE
	_rope.hide_rope()
	print("GrapplingHook: fallo")


func _release_hook() -> void:
	_state = HookState.IDLE
	_projectile.reset()
	_rope.hide_rope()
	_attached_collider = null
	Events.hook_released.emit()
	arm_state_changed.emit("Released")


## Cancelar el gancho externamente (respawn, cambio de brazo)
func cancel_hook() -> void:
	if _state != HookState.IDLE:
		_state = HookState.IDLE
		_charge_timer = 0.0
		_projectile.reset()
		_rope.hide_rope()
		_attached_collider = null


## Getters para HookedState y FlexPoleState
func get_attach_point() -> Vector3:
	return _attach_point


func get_rope_length() -> float:
	return player.global_position.distance_to(_attach_point)


func get_attached_collider() -> Node:
	return _attached_collider


func get_surface_normal() -> Vector3:
	return _surface_normal


func _physics_process(delta: float):
	match _state:
		HookState.CHARGING:
			_charge_timer += delta
		HookState.FLYING:
			_rope.update_points(_get_hand_position(), _projectile.global_position)
		HookState.ATTACHED:
			_rope.update_points(_get_hand_position(), _attach_point)


## Posicion aproximada de la mano derecha del player
func _get_hand_position() -> Vector3:
	if not player:
		return global_position
	var forward = player._skin.global_basis.z
	return player.global_position + Vector3.UP * 1.0 + forward * 0.3


## Ratio de carga actual (0.0 a 1.0) para UI/debug
func get_charge_ratio() -> float:
	if _state != HookState.CHARGING:
		return 0.0
	return clampf(_charge_timer / CHARGE_TIME, 0.0, 1.0)


## Obtiene el HookCrosshair del player (si existe)
func _get_crosshair() -> HookCrosshair:
	if player and player._hook_crosshair:
		return player._hook_crosshair
	return null
