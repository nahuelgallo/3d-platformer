class_name RopeVisual extends MeshInstance3D

# Visual de la cuerda del grappling hook.
# Usa ImmediateMesh con PRIMITIVE_LINES para dibujar una linea entre dos puntos.
# top_level = true para trabajar en coordenadas globales.

var _mesh: ImmediateMesh
var _material: StandardMaterial3D


func _ready():
	top_level = true
	# Forzar transform a identidad para que coordenadas locales = globales
	global_transform = Transform3D.IDENTITY
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.6, 0.6, 0.6)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.no_depth_test = false
	visible = false


## Dibuja la linea entre dos puntos globales
func update_points(from: Vector3, to: Vector3) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	_mesh.surface_add_vertex(from)
	_mesh.surface_add_vertex(to)
	_mesh.surface_end()
	visible = true


## Oculta la cuerda
func hide_rope() -> void:
	_mesh.clear_surfaces()
	visible = false
