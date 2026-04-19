extends CanvasLayer

# Ventana de tutorial con funciones y controles del juego.
# Toggle con la tecla 0.
# Pausa el juego mientras está abierta para que el jugador pueda leer tranquilo.

const PAUSE_ON_OPEN := true

# Estructura de secciones: cada una con titulo y pares (control, descripcion)
const SECTIONS := [
	{
		"title": "MOVIMIENTO",
		"entries": [
			["W A S D", "Moverse en el plano horizontal"],
			["Space", "Saltar (con coyote time y jump buffer)"],
			["Shift", "Correr (sprint) - sube el FOV"],
			["Ctrl", "Agacharse / Slide con momentum"],
			["Mouse", "Rotar camara"],
		],
	},
	{
		"title": "BRAZO / HOOK",
		"entries": [
			["Click Izq", "Disparar gancho (mantener para cargar)"],
			["Click Der", "Apuntar - activa bullet time (camara lenta)"],
			["Click Izq (colgado)", "Recoil: acortar cuerda hacia el punto de enganche"],
			["W / S (colgado)", "Subir / bajar por la cuerda"],
			["Q", "Cambiar de brazo (Fist / Hook)"],
		],
	},
	{
		"title": "MECANICAS",
		"entries": [
			["Bionic Hook", "Se engancha a muros, aros (RING) y postes flexibles"],
			["FlexPole", "Poste elastico que te catapulta al soltar"],
			["Hook Ring", "Aros con snap angular - alinea la mira para enganchar"],
			["Wall Cling", "Te pegas a la pared al engancharte cerca"],
			["Bullet Time", "25% de velocidad, dura hasta 1.5s reales"],
			["Slide Jump", "Slide + Salto: +35% velocidad horizontal"],
		],
	},
	{
		"title": "SISTEMA",
		"entries": [
			["0", "Abrir / cerrar este tutorial"],
			["F3", "Mostrar / ocultar HUD de debug"],
			["Esc", "Liberar el mouse"],
		],
	},
]

@onready var _content: VBoxContainer = $Panel/Margin/Root/Scroll/Content
@onready var _panel: Panel = $Panel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_content()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_tutorial"):
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	visible = not visible
	if PAUSE_ON_OPEN:
		get_tree().paused = visible
	# Liberar el mouse cuando se abre; recapturar cuando se cierra
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_content() -> void:
	for child in _content.get_children():
		child.queue_free()

	for section in SECTIONS:
		_content.add_child(_make_section_title(section["title"]))
		for entry in section["entries"]:
			_content.add_child(_make_row(entry[0], entry[1]))
		_content.add_child(_make_spacer(10))

func _make_section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	return label

func _make_row(key: String, desc: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	var key_label := Label.new()
	key_label.text = "[ %s ]" % key
	key_label.custom_minimum_size = Vector2(200, 0)
	key_label.add_theme_font_size_override("font_size", 16)
	key_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	row.add_child(key_label)

	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.add_theme_font_size_override("font_size", 16)
	desc_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc_label)

	return row

func _make_spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer
