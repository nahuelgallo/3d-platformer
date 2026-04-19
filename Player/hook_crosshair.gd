class_name HookCrosshair extends Node3D

## Mira del grappling hook. Detecta cualquier superficie del mundo via raycast
## y ademas hace snap angular a objetos pequenos (HookRing, FlexPole).
## Expone el target actual para que GrapplingHookArm lo use al disparar.

# === CONSTANTES ===
const DETECTION_RADIUS := 20.0          # Mismo que hook_max_distance
const MAX_ANGLE_DEG := 12.0             # Cono de snap angular reducido (era 30, demasiado agresivo)

const INDICATOR_COLOR_ACTIVE   := Color(0.2, 0.9, 0.4)
const INDICATOR_COLOR_INACTIVE := Color(0.5, 0.5, 0.5, 0.4)

## Raycast principal: world (1), jump-thru (3=bit2=4), hook_rings (4=bit3=8), flex_poles (7=bit6=64)
const RAYCAST_MASK := 1 | 4 | 8 | 64   # bits 0, 2, 3, 6

## Area3D de snap: solo detecta Areas de HookRing y FlexPole
const SNAP_AREA_MASK := 8 | 64          # bits 3 y 6

## Layer NO_HOOK: layer 8 = bit 7 = valor 128. Si el collider tiene este bit, no se puede enganchar.
const NO_HOOK_LAYER := 128

# === VARIABLES PUBLICAS ===
## Nodo del objetivo actual (puede ser cualquier colisionable del mundo, HookRing, FlexPole, etc.)
var current_target: Node3D = null
## Punto de mundo donde se anclaria el gancho
var current_attach_point := Vector3.ZERO
## Normal de la superficie en el punto de enganche (util para anclar en paredes/techos)
var current_surface_normal := Vector3.UP
## True si hay un objetivo valido en rango
var has_target := false
## True solo si el objetivo es un HookRing o FlexPole (no una superficie generica)
var is_special_target := false

# === VARIABLES PRIVADAS ===
var _player: CharacterBody3D
var _camera: Camera3D
var _detection_area: Area3D      # Area3D solo para snap de objetos especiales
var _indicator: MeshInstance3D
var _indicator_mat: StandardMaterial3D
var _crosshair_rect: ColorRect   # Punto central 2D en pantalla


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if not _player:
		push_warning("HookCrosshair: el padre no es CharacterBody3D")
		return

	top_level = false
	_setup_detection_area()
	_setup_3d_indicator()
	_setup_2d_crosshair()

	# Defer para que el player ya tenga sus @onready vars inicializadas
	_deferred_init.call_deferred()


func _deferred_init() -> void:
	_camera = _player._camera
	print("HookCrosshair: inicializado (camera=%s)" % [_camera != null])


# === SETUP ===

## Area3D esferica para snap angular a HookRing y FlexPole
func _setup_detection_area() -> void:
	_detection_area = Area3D.new()
	_detection_area.name = "SnapDetectionArea"
	_detection_area.collision_layer = 0    # No ocupa layer propia
	_detection_area.collision_mask = SNAP_AREA_MASK
	_detection_area.monitoring = true
	_detection_area.monitorable = false

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = DETECTION_RADIUS
	shape.shape = sphere
	_detection_area.add_child(shape)
	add_child(_detection_area)


## Indicador 3D tipo torus que aparece en el punto de enganche
func _setup_3d_indicator() -> void:
	_indicator = MeshInstance3D.new()
	_indicator.name = "HookIndicator"

	var torus := TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.35
	_indicator.mesh = torus

	_indicator_mat = StandardMaterial3D.new()
	_indicator_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_indicator_mat.albedo_color = INDICATOR_COLOR_INACTIVE
	_indicator_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_indicator_mat.no_depth_test = true
	_indicator.material_override = _indicator_mat

	# top_level para posicionar en world space sin heredar la transformacion del padre
	_indicator.top_level = true
	_indicator.visible = false
	add_child(_indicator)


## Punto central 2D del crosshair en pantalla
func _setup_2d_crosshair() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "CrosshairCanvas"
	canvas.layer = 10

	_crosshair_rect = ColorRect.new()
	_crosshair_rect.name = "Crosshair"
	_crosshair_rect.size = Vector2(4, 4)
	_crosshair_rect.color = INDICATOR_COLOR_INACTIVE
	_crosshair_rect.anchors_preset = Control.PRESET_CENTER
	_crosshair_rect.position = Vector2(-2, -2)

	canvas.add_child(_crosshair_rect)
	add_child(canvas)


# === LOOP PRINCIPAL ===

func _physics_process(_delta: float) -> void:
	if not _camera or not _detection_area:
		return

	# Mantener la detection area centrada en el player para que el overlap se actualice
	_detection_area.global_position = _player.global_position

	# 1. Raycast contra cualquier superficie del mundo
	var ray_result := _raycast_surface()

	# 2. Intentar snap angular a objetos especiales (HookRing, FlexPole)
	var snap_result := _find_snap_target()

	# 3. El snap tiene prioridad sobre el raycast si encontro algo
	if snap_result.size() > 0:
		current_target        = snap_result.target
		current_attach_point  = snap_result.point
		current_surface_normal = snap_result.get("normal", Vector3.UP)
		has_target            = true
		is_special_target     = true
	elif ray_result.size() > 0:
		current_target        = ray_result.collider
		current_attach_point  = ray_result.position
		current_surface_normal = ray_result.normal
		has_target            = true
		is_special_target     = false
	else:
		current_target        = null
		current_attach_point  = Vector3.ZERO
		current_surface_normal = Vector3.UP
		has_target            = false
		is_special_target     = false

	_update_visuals()


# === RAYCAST PRINCIPAL ===

## Dispara un rayo desde el centro de la camara hacia adelante.
## Retorna un diccionario con {collider, position, normal} si hay impacto,
## o un diccionario vacio si no hay nada valido en rango.
func _raycast_surface() -> Dictionary:
	var space := _player.get_world_3d().direct_space_state
	var cam_origin := _camera.global_position
	var cam_forward := -_camera.global_basis.z
	var ray_end := cam_origin + cam_forward * DETECTION_RADIUS

	var query := PhysicsRayQueryParameters3D.create(cam_origin, ray_end)
	query.collision_mask    = RAYCAST_MASK
	query.collide_with_areas  = false
	query.collide_with_bodies = true
	# Excluir al propio jugador (layer 2, pero mejor excluir por RID)
	query.exclude = [_player.get_rid()]

	var result := space.intersect_ray(query)
	if result.is_empty():
		return {}

	# Verificar que el collider NO tenga el layer NO_HOOK (layer 8 = bit 7 = 128)
	var col: Object = result.collider
	if col is CollisionObject3D:
		if (col as CollisionObject3D).collision_layer & NO_HOOK_LAYER:
			return {}

	return result


# === SNAP ANGULAR PARA OBJETOS ESPECIALES ===

## Escanea los Areas3D dentro del radio de deteccion y encuentra la que
## este mas centrada en la camara (menor angulo) dentro del cono de snap.
## Retorna {target, point, normal} o {} si no hay nada valido.
func _find_snap_target() -> Dictionary:
	var cam_origin  := _camera.global_position
	var cam_forward := -_camera.global_basis.z

	var best_target: Node3D = null
	var best_point  := Vector3.ZERO
	var best_angle  := MAX_ANGLE_DEG

	for area in _detection_area.get_overlapping_areas():
		var hookable := _get_hookable_parent(area)
		if not hookable:
			continue

		# Punto de enganche exacto
		var point := _get_hook_point(area, hookable)

		# Calcular angulo entre la direccion de la camara y el vector al punto
		var to_point := (point - cam_origin).normalized()
		var angle_deg := rad_to_deg(acos(clampf(cam_forward.dot(to_point), -1.0, 1.0)))

		if angle_deg < best_angle:
			# Verificar linea de vision contra geometria del mundo
			if _has_line_of_sight(cam_origin, point):
				best_angle  = angle_deg
				best_target = hookable
				best_point  = point

	if not best_target:
		return {}

	return {
		"target": best_target,
		"point":  best_point,
		"normal": Vector3.UP   # Los objetos especiales no tienen normal de superficie relevante
	}


# === HELPERS ===

## Sube desde el Area3D hasta encontrar el nodo HookRing o FlexPole padre.
## Retorna null si el area no pertenece a un hookable conocido.
func _get_hookable_parent(area: Area3D) -> Node3D:
	var parent := area.get_parent()
	if parent is HookRing or parent is FlexPole:
		return parent as Node3D
	return null


## Obtiene el punto exacto de enganche segun el tipo de hookable.
## Para FlexPole, cada Area3D hijo ya esta a la altura correcta (low/mid/high).
func _get_hook_point(area: Area3D, _hookable: Node3D) -> Vector3:
	return area.global_position


## Raycast de linea de vision: comprueba que no haya geometria del mundo
## entre la camara y el punto objetivo (evita seleccionar puntos obstruidos).
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Solo chequear contra world geometry (layer 1)
	query.collision_mask      = 1
	query.collide_with_areas  = false
	query.collide_with_bodies = true
	query.exclude = [_player.get_rid()]
	var result := space.intersect_ray(query)
	return result.is_empty()


# === VISUALES ===

func _update_visuals() -> void:
	if has_target:
		_indicator.visible = true
		_indicator.global_position = current_attach_point
		# Orientar el torus para que mire hacia la camara
		_indicator.look_at(_camera.global_position, Vector3.UP)
		_indicator_mat.albedo_color = INDICATOR_COLOR_ACTIVE
		_crosshair_rect.color = INDICATOR_COLOR_ACTIVE
	else:
		_indicator.visible = false
		_indicator_mat.albedo_color = INDICATOR_COLOR_INACTIVE
		_crosshair_rect.color = INDICATOR_COLOR_INACTIVE
