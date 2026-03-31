extends CanvasLayer

## Mira visual (punto centrado). Visible solo durante AimState.

func _ready():
	layer = 101
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(6, 6)
	dot.color = Color.WHITE
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(dot)
	Events.aim_started.connect(show)
	Events.aim_ended.connect(hide)
	hide()
