extends CanvasLayer

## HUD de estamina siempre visible. 4 barras discretas, abajo a la izquierda.
## Crea los nodos por codigo, no necesita .tscn.

var _progress_bars: Array[ProgressBar] = []

const BAR_WIDTH := 40
const BAR_HEIGHT := 12
const BAR_GAP := 4
const COLOR_FULL := Color(0.2, 0.85, 0.3)       # Verde
const COLOR_MID := Color(0.95, 0.85, 0.15)       # Amarillo
const COLOR_LOW := Color(0.7, 0.2, 0.2)          # Rojo
const COLOR_BG := Color(0.15, 0.15, 0.15, 0.8)   # Fondo oscuro


func _ready() -> void:
	layer = 10  # Encima de todo

	var margin = MarginContainer.new()
	margin.name = "StaminaMargin"
	margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	margin.anchor_left = 0.0
	margin.anchor_top = 1.0
	margin.anchor_right = 0.0
	margin.anchor_bottom = 1.0
	margin.offset_left = 20.0
	margin.offset_top = -60.0
	margin.offset_right = 20.0 + (BAR_WIDTH + BAR_GAP) * Stamina.MAX_BARS
	margin.offset_bottom = -20.0
	add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.name = "StaminaBars"
	hbox.add_theme_constant_override("separation", BAR_GAP)
	margin.add_child(hbox)

	for i in Stamina.MAX_BARS:
		var bar = ProgressBar.new()
		bar.name = "Bar%d" % i
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)

		# Estilo: fondo oscuro
		var bg_style = StyleBoxFlat.new()
		bg_style.bg_color = COLOR_BG
		bg_style.corner_radius_top_left = 2
		bg_style.corner_radius_top_right = 2
		bg_style.corner_radius_bottom_left = 2
		bg_style.corner_radius_bottom_right = 2
		bar.add_theme_stylebox_override("background", bg_style)

		# Estilo: barra de llenado
		var fill_style = StyleBoxFlat.new()
		fill_style.bg_color = COLOR_FULL
		fill_style.corner_radius_top_left = 2
		fill_style.corner_radius_top_right = 2
		fill_style.corner_radius_bottom_left = 2
		fill_style.corner_radius_bottom_right = 2
		bar.add_theme_stylebox_override("fill", fill_style)

		hbox.add_child(bar)
		_progress_bars.append(bar)


func _process(_delta: float) -> void:
	for i in Stamina.MAX_BARS:
		var val: float = Stamina.bars[i]
		_progress_bars[i].value = val

		# Color segun nivel de carga
		var fill_style: StyleBoxFlat = _progress_bars[i].get_theme_stylebox("fill")
		if val > 0.5:
			fill_style.bg_color = COLOR_FULL
		elif val > 0.2:
			fill_style.bg_color = COLOR_MID
		else:
			fill_style.bg_color = COLOR_LOW
