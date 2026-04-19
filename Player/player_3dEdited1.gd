class_name Player extends CharacterBody3D

## Controller principal del jugador.
## No contiene logica de movimiento: delega al estado activo via PlayerStateMachine.
## Maneja: camara, respawn, timers compartidos, y funciones utilitarias para los estados.

# === CONFIGURACION DE CAMARA ===
@export_group("Camera")
@export_range(0.0, 1.0) var mouse_sensitivity := 0.25
@export var camera_default_distance := 3.0
@export var camera_sprint_distance := 4.5
@export var camera_lerp_speed := 4.0
@export var camera_default_fov := 80.0
@export var camera_sprint_fov := 90.0
@export var camera_aim_distance := 2.0
@export var camera_aim_fov := 65.0
@export var camera_fov_lerp_speed := 4.0
@onready var _camera_pivot: Node3D = %CameraPivot
@onready var _camera: Camera3D = %Camera3D
@onready var _spring_arm: SpringArm3D = %SpringArm3D
@onready var _skin: RobotSkin = %RobotSkin
@onready var _state_machine: StateMachine = get_node_or_null("PlayerStateMachine")
@onready var _normal_collision: CollisionShape3D = $CollisionShape3D
@onready var _crouch_collision: CollisionShape3D = $CrouchCollisionShape3D
@onready var _arm_socket: ArmSocket = get_node_or_null("ArmSocket")
@onready var _hook_crosshair: HookCrosshair = get_node_or_null("HookCrosshair")

## Cancela cualquier accion del brazo activo (llamado al cambiar de estado)
func cancel_arm_action() -> void:
	if _arm_socket and _arm_socket.current_arm:
		if _arm_socket.current_arm.has_method("cancel_punch"):
			_arm_socket.current_arm.cancel_punch()
		if _arm_socket.current_arm.has_method("cancel_hook"):
			_arm_socket.current_arm.cancel_hook()

# === CONFIGURACION DE MOVIMIENTO ===
# Expuestos para que los estados los lean. Los valores se ajustan desde el inspector.
@export_group("Movement")
@export var move_speed := 5.0
@export var sprint_speed := 6.8
@export var crouch_speed := 4.0
@export var rotation_speed := 12.0
@export var jump_impulse := 17.4  # 45% mas alto con salto mantenido (antes: 12.0)
@export var slide_boost := 1.80
@export var slide_min_speed := 6.0

# === GAME FEEL ===
# Estos parametros controlan la "sensacion" del movimiento.
# Ajustarlos cambia drasticamente como se siente el juego.
@export_group("Game Feel")
@export var coyote_duration := 0.15  # Tiempo extra para saltar despues de caer de una plataforma
@export var jump_buffer_duration := 0.25  # Si presionas salto antes de tocar el suelo, se ejecuta al aterrizar
@export var fall_gravity_multiplier := 1.8  # Caer se siente mas pesado que subir (juiciness)
@export var jump_cut_multiplier := 0.28  # Soltar temprano = salto corto similar al original

# === VARIABLES INTERNAS ===
# Compartidas con los estados a traves de la referencia al player.
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var dash_cooldown := 0.0  # Cooldown entre dashes (suelo y aire)
var dash_cooldown_paused := false  # Pausa el cooldown durante el sprint post-dash
var slide_cooldown := 0.0  # Cooldown entre slides
var _pre_move_y_velocity := 0.0  # Velocidad Y antes de move_and_slide (para calcular impacto del landing)
var is_punching := false  # True durante la animacion de golpe, bloquea movimiento

var bullet_time_ratio := 0.0  # 0.0 = sin bullet time, 1.0 = lleno. Los estados lo actualizan.

var _target_camera_distance := 3.0
var _target_camera_fov := 80.0
var _camera_input_direction := Vector2.ZERO
var _last_movement_direction := Vector3.BACK
var _gravity := -30.0
var _spawn_position := Vector3.ZERO  # Posicion inicial para respawn


func _ready():
	add_to_group("player")
	# Guardar posicion de spawn para respawn al morir
	_spawn_position = global_position
	_target_camera_distance = camera_default_distance
	_target_camera_fov = camera_default_fov
	Events.kill_plane_touched.connect(_respawn)
	Events.checkpoint_reached.connect(func(pos: Vector3): _spawn_position = pos)
	# Asegurar que el collider de crouch arranca desactivado
	if _crouch_collision:
		_crouch_collision.disabled = true
	# Conectar senales del brazo activo
	if _arm_socket and _arm_socket.current_arm:
		_connect_arm_signals(_arm_socket.current_arm)


func _respawn():
	# Cancelar gancho/brazo antes de respawnear
	cancel_arm_action()
	# Resetear posicion y velocidad al punto de spawn
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_skin.is_landing = false
	_skin.idle()
	if _state_machine:
		_state_machine.transition_to("Idle")


func _physics_process(delta: float) -> void:
	# Solo camara y timers. El movimiento lo maneja el estado activo
	# (via StateMachine._physics_process que corre despues de este).

	# --- CAMARA ---
	_camera_pivot.rotation.x = clamp(
		_camera_pivot.rotation.x + _camera_input_direction.y * delta,
		-PI * 0.47, # ~85 grados arriba (casi techo)
		PI / 3.0    # ~60 grados abajo
	)
	_camera_pivot.rotation.y -= _camera_input_direction.x * delta
	_camera_input_direction = Vector2.ZERO

	# --- DISTANCIA DE CAMARA ---
	if _spring_arm:
		_spring_arm.spring_length = lerp(_spring_arm.spring_length, _target_camera_distance, camera_lerp_speed * delta)

	# --- FOV DE CAMARA ---
	if _camera:
		_camera.fov = lerp(_camera.fov, _target_camera_fov, camera_fov_lerp_speed * delta)

	# --- JUMP BUFFER TIMER ---
	# Se actualiza aca (antes de la state machine) para que el estado activo
	# siempre lea el valor correcto. is_action_just_pressed solo dura un frame.
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_duration
	else:
		jump_buffer_timer -= delta

	# --- COOLDOWNS ---
	# Dash: pausado solo durante el sprint donde se hizo el dash
	# Al soltar sprint se despausa y no vuelve a pausarse
	if dash_cooldown_paused and not Input.is_action_pressed("sprint"):
		dash_cooldown_paused = false
	if not dash_cooldown_paused:
		dash_cooldown -= delta
	slide_cooldown -= delta


# === FUNCIONES UTILITARIAS PARA LOS ESTADOS ===

## Calcula la direccion de movimiento relativa a la camara.
func get_move_direction() -> Vector3:
	var raw_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := (_camera.global_basis.z * raw_input.y + _camera.global_basis.x * raw_input.x)
	dir.y = 0.0
	return dir.normalized()


## Aplica gravedad asimetrica (caer mas rapido que subir).
func apply_gravity(delta: float) -> void:
	var grav := _gravity
	if velocity.y < 0.0:
		grav *= fall_gravity_multiplier
	velocity.y += grav * delta


## Rota el modelo suavemente hacia la direccion de movimiento.
func rotate_skin(delta: float) -> void:
	var move_dir := get_move_direction()
	if move_dir.length() > 0.2:
		_last_movement_direction = move_dir
	var target_angle := Vector3.BACK.signed_angle_to(_last_movement_direction, Vector3.UP)
	_skin.global_rotation.y = lerp_angle(_skin.global_rotation.y, target_angle, rotation_speed * delta)


## Ejecuta un salto: aplica impulso, resetea timers, efectos visuales.
## Los estados deciden CUANDO llamar esto; esta funcion solo hace el HOW.
func perform_jump() -> void:
	velocity.y = jump_impulse
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	apply_squash_and_stretch(Vector3(0.7, 1.4, 0.7))
	_skin.jump()


## Step-up: intenta subir micro-escalones antes de move_and_slide.
## Solo usar en estados de suelo (walk, run, idle). En aire usar move_and_slide normal.
const STEP_HEIGHT := 0.35

func move_with_step_up() -> void:
	if not is_on_floor():
		move_and_slide()
		return
	var start_pos = global_position
	var start_vel = velocity
	# Intento normal
	move_and_slide()
	# Si choque con pared estando en el suelo, intentar step-up
	var hit_wall = false
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		if col.get_normal().y < 0.1:
			hit_wall = true
			break
	if not hit_wall:
		return
	# Guardar resultado del intento normal para comparar
	var normal_pos = global_position
	# Restaurar y re-intentar con step-up
	global_position = start_pos
	velocity = start_vel
	# Subir
	var up_col = move_and_collide(Vector3.UP * STEP_HEIGHT)
	var actual_step = STEP_HEIGHT
	if up_col:
		actual_step = STEP_HEIGHT - up_col.get_remainder().length()
	# Avanzar
	move_and_slide()
	# Bajar
	move_and_collide(Vector3.DOWN * (actual_step + 0.05))
	# Si no avanzo mas que el intento normal, revertir
	var step_pos = global_position
	var normal_advance = normal_pos.distance_squared_to(start_pos)
	var step_advance = step_pos.distance_squared_to(start_pos)
	if step_advance <= normal_advance:
		global_position = normal_pos
		velocity = start_vel


## Squash & stretch: deformacion temporal del modelo para dar "juiciness".
func apply_squash_and_stretch(target_scale: Vector3) -> void:
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_skin.scale = target_scale
	tween.tween_property(_skin, "scale", Vector3.ONE, 0.15)


## Intercambia entre collider normal y reducido para crouch/slide.
func set_crouching(enabled: bool) -> void:
	if _normal_collision and _crouch_collision:
		_normal_collision.disabled = enabled
		_crouch_collision.disabled = not enabled


## Verifica si hay espacio para pararse (no hay techo encima).
## Usa un ShapeCast desde la posicion actual hacia arriba para detectar techo.
func can_stand_up() -> bool:
	if not _normal_collision or not _crouch_collision:
		return true
	# Calcular cuanto mas alto es el collider normal vs el de crouch
	var normal_shape = _normal_collision.shape as CapsuleShape3D
	var crouch_shape = _crouch_collision.shape as CapsuleShape3D
	if not normal_shape or not crouch_shape:
		return true
	var height_diff = normal_shape.height - crouch_shape.height
	if height_diff <= 0.0:
		return true
	# Hacer un raycast desde la parte superior del crouch collider hacia arriba
	var space = get_world_3d().direct_space_state
	var top_y = _crouch_collision.global_position.y + crouch_shape.height * 0.5
	var from = Vector3(global_position.x, top_y, global_position.z)
	var to = from + Vector3.UP * height_diff
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result = space.intersect_ray(query)
	return result.is_empty()


## Devuelve el nombre del estado activo para el Debug HUD.
func _get_debug_state() -> String:
	if _state_machine and _state_machine.current_state:
		return _state_machine.current_state.name.to_upper()
	return "???"


## Conecta la senal arm_state_changed de un brazo (si la tiene)
func _connect_arm_signals(arm: Node3D) -> void:
	if arm.has_signal("arm_state_changed"):
		if not arm.is_connected("arm_state_changed", _on_arm_state_changed):
			arm.arm_state_changed.connect(_on_arm_state_changed)


## Desconecta la senal arm_state_changed de un brazo
func _disconnect_arm_signals(arm: Node3D) -> void:
	if arm.has_signal("arm_state_changed"):
		if arm.is_connected("arm_state_changed", _on_arm_state_changed):
			arm.arm_state_changed.disconnect(_on_arm_state_changed)


## Reacciona al cambio de estado del brazo activo
func _on_arm_state_changed(new_state: String) -> void:
	match new_state:
		"Hooked":
			if _arm_socket and _arm_socket.current_arm:
				var arm = _arm_socket.current_arm
				var attach_point = arm.get_attach_point() if arm.has_method("get_attach_point") else Vector3.ZERO
				var rope_length = arm.get_rope_length() if arm.has_method("get_rope_length") else 5.0
				var surface_normal = arm.get_surface_normal() if arm.has_method("get_surface_normal") else Vector3.DOWN
				var hook_ring = arm.is_hook_ring() if arm.has_method("is_hook_ring") else false
				if _state_machine:
					_state_machine.transition_to("Hooked", {
						"attach_point": attach_point,
						"rope_length": rope_length,
						"surface_normal": surface_normal,
						"is_hook_ring": hook_ring
					})
		"FlexPoleHooked":
			if _arm_socket and _arm_socket.current_arm:
				var arm = _arm_socket.current_arm
				var attached_collider = arm.get_attached_collider() if arm.has_method("get_attached_collider") else null
				var flex_pole = _find_flex_pole_from_collider(attached_collider)
				var hit_point = arm.get_attach_point() if arm.has_method("get_attach_point") else Vector3.ZERO
				if flex_pole and _state_machine:
					_state_machine.transition_to("FlexPole", {
						"flex_pole": flex_pole,
						"hit_y": hit_point.y
					})
		"Released":
			if _state_machine and _state_machine.current_state:
				var state_name = _state_machine.current_state.name
				if state_name == "Hooked" or state_name == "FlexPole":
					_state_machine.transition_to("Airborne")


## Busca el FlexPole subiendo por el arbol de nodos desde el collider
func _find_flex_pole_from_collider(collider: Node) -> FlexPole:
	if not collider:
		return null
	if collider is FlexPole:
		return collider
	var parent = collider.get_parent()
	while parent:
		if parent is FlexPole:
			return parent
		parent = parent.get_parent()
	return null


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("left_click"):
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			# Consumir el evento para que no llegue a _unhandled_input
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_camera_input_direction = event.screen_relative * mouse_sensitivity

	# === SWITCH DE BRAZO ===
	if _arm_socket and event.is_action_pressed("switch_arm"):
		var old_arm = _arm_socket.current_arm
		if old_arm:
			_disconnect_arm_signals(old_arm)
		_arm_socket.switch_arm()
		if _arm_socket.current_arm:
			_connect_arm_signals(_arm_socket.current_arm)

	# === INPUTS DE BRAZO ===
	if _arm_socket and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event.is_action_pressed("left_click"):
			_arm_socket.primary_action()
		if event.is_action_pressed("right_click"):
			_arm_socket.secondary_action()
		if event.is_action_released("left_click"):
			_arm_socket.release_action()
