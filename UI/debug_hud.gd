extends CanvasLayer

# HUD de debug para desarrollo.
# Muestra velocidad, estado y FPS en pantalla.
# Toggle con F3.
# Iconos de habilidades siempre visibles.

@onready var label: Label = $Label
@onready var run_icon: Label = $AbilityBar/RunIcon
@onready var dash_icon: Label = $AbilityBar/DashIcon
@onready var fast_drop_icon: Label = $AbilityBar/FastDropIcon
@onready var slide_icon: Label = $AbilityBar/SlideIcon
var player: CharacterBody3D
var _arm_canvas: CanvasLayer
var _arm_label: Label

const OPACITY_LOCKED := 0.25
const OPACITY_COOLDOWN := 0.5
const OPACITY_READY := 1.0

func _ready():
	# Buscar al jugador. El HUD debe ser hijo del Player o del nivel.
	player = get_parent() as CharacterBody3D
	if not player:
		# Si no es hijo directo del player, buscar en el arbol
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	visible = false
	# CanvasLayer separado para el indicador de brazo (siempre visible, independiente de F3)
	_arm_canvas = CanvasLayer.new()
	_arm_canvas.name = "ArmCanvas"
	_arm_canvas.layer = 99
	get_parent().add_child.call_deferred(_arm_canvas)

	_arm_label = Label.new()
	_arm_label.name = "ArmLabel"
	_arm_label.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	_arm_label.anchor_left = 1.0
	_arm_label.anchor_top = 1.0
	_arm_label.anchor_right = 1.0
	_arm_label.anchor_bottom = 1.0
	_arm_label.offset_left = -220.0
	_arm_label.offset_top = -50.0
	_arm_label.offset_right = -12.0
	_arm_label.offset_bottom = -12.0
	_arm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_arm_label.add_theme_font_size_override("font_size", 22)
	_arm_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_arm_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_arm_label.add_theme_constant_override("shadow_offset_x", 2)
	_arm_label.add_theme_constant_override("shadow_offset_y", 2)
	_arm_canvas.add_child(_arm_label)

func _unhandled_input(event: InputEvent):
	# F3 para mostrar/ocultar el HUD de debug
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = !visible

func _process(_delta: float):
	if not player:
		return

	# Iconos de habilidades (siempre visibles)
	_update_ability_icons()
	# Brazo activo (siempre visible)
	_update_arm_label()

	if not visible:
		return

	var vel = player.velocity
	var h_speed = Vector2(vel.x, vel.z).length()

	# Determinar estado actual del jugador para mostrarlo
	var state := "???"
	if player.has_method("_get_debug_state"):
		state = player._get_debug_state()
	else:
		if not player.is_on_floor():
			state = "AIR (%.1f)" % vel.y
		elif h_speed < 0.5:
			state = "IDLE"
		elif Input.is_action_pressed("sprint"):
			state = "RUN"
		elif Input.is_action_pressed("crouch"):
			state = "CROUCH"
		else:
			state = "WALK"

	# Brazo activo
	var arm_name := "---"
	if player._arm_socket and player._arm_socket.current_arm:
		arm_name = player._arm_socket.current_arm.name

	label.text = "=== DEBUG (F3) ===\nFPS: %d\nSpeed: %.1f\nH-Speed: %.1f\nV-Speed: %.1f\nState: %s\nArm: %s\nPos: (%.1f, %.1f, %.1f)" % [
		Engine.get_frames_per_second(),
		vel.length(),
		h_speed,
		vel.y,
		state,
		arm_name,
		player.global_position.x,
		player.global_position.y,
		player.global_position.z
	]


func _update_ability_icons():
	_set_icon(run_icon, "🏃", Abilities.run_unlocked, true)
	_set_icon(dash_icon, "💨", Abilities.dash_unlocked, player.dash_cooldown <= 0.0)
	_set_icon(fast_drop_icon, "⬇️", Abilities.fast_drop_unlocked, true)
	_set_icon(slide_icon, "👟", Abilities.slide_unlocked, player.slide_cooldown <= 0.0)


func _update_arm_label():
	if not _arm_label or not player:
		return
	var arm_text := "❌ ---"
	if player._arm_socket and player._arm_socket.current_arm:
		var arm_name = player._arm_socket.current_arm.name
		match arm_name:
			"FistArm":
				arm_text = "👊 Fist"
			"GrapplingHook":
				arm_text = "🪝 Hook"
			_:
				arm_text = "🔧 %s" % arm_name
	_arm_label.text = "[Q] %s" % arm_text


func _set_icon(icon: Label, emoji: String, unlocked: bool, ready: bool):
	if not icon:
		return
	if not unlocked:
		icon.text = emoji
		icon.modulate.a = OPACITY_LOCKED
	elif not ready:
		icon.text = "⏳"
		icon.modulate.a = OPACITY_READY
	else:
		icon.text = emoji
		icon.modulate.a = OPACITY_READY
