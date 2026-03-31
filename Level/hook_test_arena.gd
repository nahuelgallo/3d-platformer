class_name HookTestArena extends Node3D

## Generador de nivel de prueba para hook mechanics.
## Crea 4 zonas modulares + hub central al iniciar la escena.
## Attach este script a un Node3D en test_level.tscn y las zonas aparecen automaticamente.

# Colores para identificar zonas visualmente
const COLOR_HUB := Color(0.3, 0.6, 0.9)       # Azul claro
const COLOR_ZONE1 := Color(0.9, 0.6, 0.2)     # Naranja (swing basico)
const COLOR_ZONE2 := Color(0.3, 0.9, 0.4)     # Verde (flex poles)
const COLOR_ZONE3 := Color(0.6, 0.3, 0.9)     # Violeta (swing encadenado)
const COLOR_ZONE4 := Color(0.9, 0.3, 0.3)     # Rojo (combo)
const COLOR_RING := Color(0.9, 0.8, 0.1)       # Amarillo (hook rings)


func _ready():
	_build_hub()
	_build_zone1_swing_basico()
	_build_zone2_flex_poles()
	_build_zone3_chain_swing()
	_build_zone4_combo()
	print("HookTestArena: nivel generado con 4 zonas + hub")


# ============================================================
# HUB CENTRAL
# ============================================================
func _build_hub():
	var hub = Node3D.new()
	hub.name = "Hub"
	add_child(hub)

	# Plataforma principal grande
	_add_platform(hub, Vector3(0, -0.5, 0), Vector3(24, 1, 24), COLOR_HUB)

	# Corredores a cada zona
	_add_platform(hub, Vector3(0, -0.5, -22), Vector3(6, 1, 24), COLOR_HUB)  # Norte -> Z1
	_add_platform(hub, Vector3(22, -0.5, 0), Vector3(24, 1, 6), COLOR_HUB)   # Este -> Z2
	_add_platform(hub, Vector3(-22, -0.5, 0), Vector3(24, 1, 6), COLOR_HUB)  # Oeste -> Z3
	_add_platform(hub, Vector3(0, -0.5, 22), Vector3(6, 1, 24), COLOR_HUB)   # Sur -> Z4

	# Checkpoint en el hub
	_add_checkpoint(hub, Vector3(0, 0, 0))


# ============================================================
# ZONA 1: SWING BASICO (Norte)
# ============================================================
func _build_zone1_swing_basico():
	var zone = Node3D.new()
	zone.name = "Zone1_SwingBasico"
	zone.position = Vector3(0, 0, -45)
	add_child(zone)

	# Plataforma de inicio
	_add_platform(zone, Vector3(0, -0.5, 0), Vector3(8, 1, 8), COLOR_ZONE1)
	_add_checkpoint(zone, Vector3(0, 0, 0))

	# Ring 1 + plataforma intermedia
	_add_hook_ring(zone, Vector3(0, 10, -10))
	_add_platform(zone, Vector3(0, 1.5, -18), Vector3(6, 1, 6), COLOR_ZONE1)

	# Ring 2 + plataforma intermedia
	_add_hook_ring(zone, Vector3(0, 12, -26))
	_add_platform(zone, Vector3(0, 3, -35), Vector3(6, 1, 6), COLOR_ZONE1)

	# Ring 3 (distancia larga) + plataforma final
	_add_hook_ring(zone, Vector3(0, 14, -45))
	_add_platform(zone, Vector3(0, 5, -56), Vector3(8, 1, 8), COLOR_ZONE1)

	# Ring 4 extra alto para testear carga maxima
	_add_hook_ring(zone, Vector3(0, 18, -64))
	_add_platform(zone, Vector3(0, 8, -74), Vector3(8, 1, 8), COLOR_ZONE1)


# ============================================================
# ZONA 2: FLEX POLES (Este)
# ============================================================
func _build_zone2_flex_poles():
	var zone = Node3D.new()
	zone.name = "Zone2_FlexPoles"
	zone.position = Vector3(45, 0, 0)
	add_child(zone)

	# Suelo amplio para experimentar
	_add_platform(zone, Vector3(0, -0.5, 0), Vector3(40, 1, 40), COLOR_ZONE2)
	_add_checkpoint(zone, Vector3(-15, 0, 0))

	# Pole 1 — bajo, suave (para aprender la mecanica)
	var pole1 = _add_flex_pole(zone, Vector3(-8, 0, -8))
	pole1.pole_height = 4.0
	pole1.launch_force_max = 22.0
	# Target platform arriba
	_add_platform(zone, Vector3(-8, 8, -16), Vector3(5, 1, 5), COLOR_ZONE2.lightened(0.2))

	# Pole 2 — medio (default)
	var pole2 = _add_flex_pole(zone, Vector3(6, 0, 0))
	pole2.pole_height = 6.0
	pole2.launch_force_max = 30.0
	# Target platforms a distintas distancias
	_add_platform(zone, Vector3(14, 12, 0), Vector3(5, 1, 5), COLOR_ZONE2.lightened(0.2))
	_add_platform(zone, Vector3(6, 10, -10), Vector3(4, 1, 4), COLOR_ZONE2.lightened(0.3))

	# Pole 3 — alto, potente
	var pole3 = _add_flex_pole(zone, Vector3(-4, 0, 10))
	pole3.pole_height = 8.0
	pole3.launch_force_max = 42.0
	# Target platform alto
	_add_platform(zone, Vector3(-4, 18, 20), Vector3(5, 1, 5), COLOR_ZONE2.lightened(0.2))

	# Pole 4 — challenge: alejado, necesita angulo preciso
	var pole4 = _add_flex_pole(zone, Vector3(10, 0, 12))
	pole4.pole_height = 7.0
	pole4.launch_force_max = 38.0
	# Target lejano
	_add_platform(zone, Vector3(10, 14, 26), Vector3(4, 1, 4), COLOR_ZONE2.lightened(0.4))


# ============================================================
# ZONA 3: SWING ENCADENADO (Oeste)
# ============================================================
func _build_zone3_chain_swing():
	var zone = Node3D.new()
	zone.name = "Zone3_ChainSwing"
	zone.position = Vector3(-45, 0, 0)
	add_child(zone)

	# Plataforma de inicio
	_add_platform(zone, Vector3(0, -0.5, 0), Vector3(8, 1, 8), COLOR_ZONE3)
	_add_checkpoint(zone, Vector3(0, 0, 0))

	# Hook rings en zigzag — sin suelo entre ellos
	_add_hook_ring(zone, Vector3(-5, 12, -8))
	_add_hook_ring(zone, Vector3(5, 14, -18))
	_add_hook_ring(zone, Vector3(-5, 13, -28))
	_add_hook_ring(zone, Vector3(5, 15, -38))
	_add_hook_ring(zone, Vector3(-5, 14, -48))
	_add_hook_ring(zone, Vector3(5, 16, -58))

	# Plataforma final
	_add_platform(zone, Vector3(0, 2, -66), Vector3(8, 1, 8), COLOR_ZONE3)

	# Bonus: ruta alta con rings mas separados para speedrun
	_add_hook_ring(zone, Vector3(0, 20, -20))
	_add_hook_ring(zone, Vector3(0, 22, -45))


# ============================================================
# ZONA 4: COMBO / FLOW (Sur)
# ============================================================
func _build_zone4_combo():
	var zone = Node3D.new()
	zone.name = "Zone4_Combo"
	zone.position = Vector3(0, 0, 45)
	add_child(zone)

	# Start platform
	_add_platform(zone, Vector3(0, -0.5, 0), Vector3(8, 1, 8), COLOR_ZONE4)
	_add_checkpoint(zone, Vector3(0, 0, 0))

	# Section A: Hook ring swing across gap
	_add_hook_ring(zone, Vector3(0, 10, 10))
	_add_platform(zone, Vector3(0, 1.5, 20), Vector3(6, 1, 6), COLOR_ZONE4)

	# Section B: Flex pole catapult up
	var combo_pole = _add_flex_pole(zone, Vector3(0, 1.5, 26))
	combo_pole.pole_height = 6.0
	combo_pole.launch_force_max = 36.0
	# Target platform alto
	_add_platform(zone, Vector3(0, 16, 34), Vector3(6, 1, 6), COLOR_ZONE4)

	# Section C: Rampa para slide
	_add_ramp(zone, Vector3(0, 8, 40), Vector3(6, 1, 14), -25.0, COLOR_ZONE4.darkened(0.2))
	# Flat area para slide
	_add_platform(zone, Vector3(0, 1.5, 52), Vector3(8, 1, 12), COLOR_ZONE4)

	# Section D: Hook to finish
	_add_hook_ring(zone, Vector3(0, 12, 62))
	# Final platform
	_add_platform(zone, Vector3(0, 4, 72), Vector3(8, 1, 8), COLOR_ZONE4)


# ============================================================
# HELPERS — Crean nodos de nivel
# ============================================================

## Crea una plataforma solida (StaticBody3D + CollisionShape3D + visual)
func _add_platform(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.name = "Platform_%d" % parent.get_child_count()
	body.position = pos

	# Collision
	var col = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = size
	col.shape = box_shape
	body.add_child(col)

	# Visual
	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)

	parent.add_child(body)
	return body


## Crea una rampa (plataforma rotada)
func _add_ramp(parent: Node3D, pos: Vector3, size: Vector3, angle_deg: float, color: Color) -> StaticBody3D:
	var body = _add_platform(parent, pos, size, color)
	body.rotation_degrees.x = angle_deg
	return body


## Crea un hook ring (Area3D en layer 4 con visual de torus)
func _add_hook_ring(parent: Node3D, pos: Vector3) -> Node3D:
	var ring = Node3D.new()
	ring.name = "HookRing_%d" % parent.get_child_count()
	ring.position = pos

	# Area3D para deteccion
	var area = Area3D.new()
	area.name = "Area3D"
	area.collision_layer = 8   # Layer 4 (hook_points)
	area.collision_mask = 0
	area.monitorable = true
	area.monitoring = false

	var col = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 1.0
	col.shape = sphere
	area.add_child(col)
	ring.add_child(area)

	# Visual: torus amarillo
	var mesh_inst = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 1.0
	mesh_inst.mesh = torus
	var mat = StandardMaterial3D.new()
	mat.albedo_color = COLOR_RING
	mat.emission_enabled = true
	mat.emission = COLOR_RING
	mat.emission_energy_multiplier = 0.5
	mesh_inst.material_override = mat
	ring.add_child(mesh_inst)

	# Asignar script de HookRing si existe
	var hook_ring_script = load("res://Level/Elements/hook_ring.gd")
	if hook_ring_script:
		ring.set_script(hook_ring_script)

	parent.add_child(ring)
	return ring


## Crea un FlexPole
func _add_flex_pole(parent: Node3D, pos: Vector3) -> FlexPole:
	var pole = FlexPole.new()
	pole.name = "FlexPole_%d" % parent.get_child_count()
	pole.position = pos
	parent.add_child(pole)
	return pole


## Crea un checkpoint (Area3D en layer 6)
func _add_checkpoint(parent: Node3D, pos: Vector3) -> void:
	var cp = Area3D.new()
	cp.name = "Checkpoint_%d" % parent.get_child_count()
	cp.position = pos
	cp.collision_layer = 32  # Layer 6 (interactables)
	cp.collision_mask = 2    # Layer 2 (player)
	cp.monitoring = true
	cp.monitorable = false

	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(3, 4, 3)
	col.shape = box
	cp.add_child(col)

	# Visual: poste indicador
	var mesh_inst = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.1
	cylinder.bottom_radius = 0.1
	cylinder.height = 3.0
	mesh_inst.mesh = cylinder
	mesh_inst.position = Vector3(0, 1.5, 0)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.9, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.9, 0.1)
	mat.emission_energy_multiplier = 0.3
	mesh_inst.material_override = mat
	cp.add_child(mesh_inst)

	# Conectar senal de checkpoint
	cp.body_entered.connect(func(body):
		if body.is_in_group("player"):
			Events.checkpoint_reached.emit(cp.global_position + Vector3(0, 1, 0))
	)

	parent.add_child(cp)
