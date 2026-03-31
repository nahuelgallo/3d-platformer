class_name HookCrosshair extends Node3D

## Mira del grappling hook. Detecta puntos enganchables y selecciona
## el mejor candidato por proximidad angular al centro de la camara.
## Expone el target actual para que GrapplingHookArm lo use al disparar.

const DETECTION_RADIUS := 20.0   # Mismo que hook_max_distance
const MAX_ANGLE_DEG := 30.0      # Cono de deteccion en grados
const INDICATOR_COLOR_ACTIVE := Color(0.2, 0.9, 0.4)
const INDICATOR_COLOR_INACTIVE := Color(0.5, 0.5, 0.5, 0.4)

## Layers detectables: layer 3 (jump-thru=bit2), layer 4 (hook_points=bit3), layer 7 (flex_poles=bit6)
const HOOKABLE_MASK := 0b1001100  # bits 2, 3, 6

var current_target: Node3D = null
var current_attach_point := Vector3.ZERO
var has_target := false

var _player: CharacterBody3D
var _camera: Camera3D
var _detection_area: Area3D
var _indicator: MeshInstance3D
var _indicator_mat: StandardMaterial3D

# Crosshair 2D en pantalla
var _crosshair_rect: ColorRect


func _ready():
	_player = get_parent() as CharacterBody3D
	if not _player:
		push_warning("HookCrosshair: parent is not CharacterBody3D")
		return

	top_level = false
	_setup_detection_area()
	_setup_3d_indicator()
	_setup_2d_crosshair()

	# Defer para que el player ya tenga sus @onready vars inicializadas
	_deferred_init.call_deferred()


func _deferred_init():
	_camera = _player._camera
	print("HookCrosshair: inicializado (camera=%s)" % [_camera != null])


func _setup_detection_area():
	_detection_area = Area3D.new()
	_detection_area.name = "DetectionArea"
	# No ocupa collision layer propia, solo monitorea
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = HOOKABLE_MASK
	_detection_area.monitoring = true
	_detection_area.monitorable = false

	var shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = DETECTION_RADIUS
	shape.shape = sphere
	_detection_area.add_child(shape)
	add_child(_detection_area)


func _setup_3d_indicator():
	# Indicador 3D que aparece en el punto de enganche
	_indicator = MeshInstance3D.new()
	_indicator.name = "HookIndicator"
	var torus = TorusMesh.new()
	torus.inner_radius = 0.15
	torus.outer_radius = 0.35
	_indicator.mesh = torus

	_indicator_mat = StandardMaterial3D.new()
	_indicator_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_indicator_mat.albedo_color = INDICATOR_COLOR_INACTIVE
	_indicator_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_indicator_mat.no_depth_test = true
	_indicator.material_override = _indicator_mat

	# Top level para posicionar en world space
	_indicator.top_level = true
	_indicator.visible = false
	add_child(_indicator)


func _setup_2d_crosshair():
	# Crosshair simple en el centro de la pantalla
	var canvas = CanvasLayer.new()
	canvas.name = "CrosshairCanvas"
	canvas.layer = 10

	_crosshair_rect = ColorRect.new()
	_crosshair_rect.name = "Crosshair"
	_crosshair_rect.size = Vector2(4, 4)
	_crosshair_rect.color = INDICATOR_COLOR_INACTIVE
	# Centrar con anchors
	_crosshair_rect.anchors_preset = Control.PRESET_CENTER
	_crosshair_rect.position = Vector2(-2, -2)

	canvas.add_child(_crosshair_rect)
	add_child(canvas)


func _physics_process(_delta: float):
	if not _camera or not _detection_area:
		return

	# Mantener la detection area centrada en el player
	_detection_area.global_position = _player.global_position

	var best_target: Node3D = null
	var best_point := Vector3.ZERO
	var best_angle := MAX_ANGLE_DEG

	var cam_origin := _camera.global_position
	var cam_forward := -_camera.global_basis.z

	# Evaluar areas en rango (HookRing, FlexPole)
	for area in _detection_area.get_overlapping_areas():
		var hookable = _get_hookable_parent(area)
		if not hookable:
			continue

		var point = _get_hook_point(area, hookable)
		var to_point = (point - cam_origin).normalized()
		var angle_deg = rad_to_deg(acos(clampf(cam_forward.dot(to_point), -1.0, 1.0)))

		if angle_deg < best_angle:
			if _has_line_of_sight(cam_origin, point):
				best_angle = angle_deg
				best_target = hookable
				best_point = point

	# Evaluar bodies en rango (JumpThruPlatform es AnimatableBody3D, no Area3D)
	for body in _detection_area.get_overlapping_bodies():
		var hookable = _get_hookable_body(body)
		if not hookable:
			continue

		var point = body.global_position
		var to_point = (point - cam_origin).normalized()
		var angle_deg = rad_to_deg(acos(clampf(cam_forward.dot(to_point), -1.0, 1.0)))

		if angle_deg < best_angle:
			if _has_line_of_sight(cam_origin, point):
				best_angle = angle_deg
				best_target = hookable
				best_point = point

	# Actualizar estado
	current_target = best_target
	current_attach_point = best_point
	has_target = best_target != null

	_update_visuals()


## Sube por el arbol de nodos desde el Area3D para encontrar
## el nodo hookable (HookRing o FlexPole)
func _get_hookable_parent(area: Area3D) -> Node3D:
	var parent = area.get_parent()
	if parent is HookRing or parent is FlexPole:
		return parent
	return null


## Identifica bodies hookables (JumpThruPlatform)
func _get_hookable_body(body: Node3D) -> Node3D:
	if body is JumpThruPlatform:
		return body
	var parent = body.get_parent()
	if parent is JumpThruPlatform:
		return parent
	return null


## Obtiene el punto exacto de enganche del hookable
func _get_hook_point(area: Area3D, hookable: Node3D) -> Vector3:
	# Para FlexPole, usar la posicion del HookPoint
	if hookable is FlexPole and hookable.has_method("get_hook_point_position"):
		return hookable.get_hook_point_position()
	# Para HookRing y otros, usar la posicion del area
	return area.global_position


## Raycast para verificar que no hay geometria del mundo entre la camara y el punto
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space = _player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	# Solo chequear contra mundo (layer 1)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [_player.get_rid()]
	var result = space.intersect_ray(query)
	return result.is_empty()


func _update_visuals():
	if has_target:
		_indicator.visible = true
		_indicator.global_position = current_attach_point
		# Orientar el torus hacia la camara
		_indicator.look_at(_camera.global_position, Vector3.UP)
		_indicator_mat.albedo_color = INDICATOR_COLOR_ACTIVE
		_crosshair_rect.color = INDICATOR_COLOR_ACTIVE
	else:
		_indicator.visible = false
		_indicator_mat.albedo_color = INDICATOR_COLOR_INACTIVE
		_crosshair_rect.color = INDICATOR_COLOR_INACTIVE
