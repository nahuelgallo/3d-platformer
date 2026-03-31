# Hook Crosshair, Flex Pole & Test Level — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hook crosshair that shows where the grappling hook will attach, a flex pole (tree slingshot) level element with dedicated player state, and a modular test level arena with 4 zones for testing all hook mechanics.

**Architecture:** The crosshair is a player child node that scans for hookable targets each frame using angular priority. The flex pole is a Level/Elements node on collision layer 7, with a dedicated FlexPoleState in the player state machine. The test level is rebuilt as a modular arena with hub + 4 zones covering ~70% of the surface.

**Tech Stack:** Godot 4.5, GDScript, CharacterBody3D, StateMachine pattern

**Spec:** `docs/superpowers/specs/2026-03-31-hook-crosshair-flexpole-testlevel-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Player/hook_crosshair.gd` | Scans for hookable targets, selects best by angle, exposes target info, manages 3D indicator |
| `Player/States/flex_pole_state.gd` | Player state when attached to flex pole — orbit, bend, launch |
| `Level/Elements/flex_pole.gd` | Flex pole logic — bend amount, launch calculation, visual bending |
| `Level/Elements/flex_pole.tscn` | Flex pole scene (Node3D with mesh, hook point, collision) |

### Modified Files
| File | Changes |
|------|---------|
| `Events.gd` | Add `pole_grabbed` and `pole_launched` signals |
| `project.godot` | Add layer 7 name `flex_poles` |
| `Player/player_3dEdited1.gd` | Add `_on_arm_state_changed` case for `"FlexPoleHooked"`, add crosshair reference |
| `Player/Arms/GrapplingHook/grappling_hook_arm.gd` | Use crosshair target when firing, detect FlexPole vs HookRing on hit |
| `Level/test_level.tscn` | Rebuild as modular arena with 4 zones (done in Godot editor, guided by script-generated structure) |

---

## Task 1: Foundation — Events + Collision Layer

**Files:**
- Modify: `Events.gd:1-10`
- Modify: `project.godot` (layer_names section)

- [ ] **Step 1: Add new signals to Events.gd**

Add two new signals for flex pole communication:

```gdscript
# Events.gd — add after line 10 (hook_released)
signal pole_grabbed(pole_position: Vector3)
signal pole_launched(launch_velocity: Vector3)
```

Full file after edit:
```gdscript
extends Node

signal kill_plane_touched
signal flag_reached
signal checkpoint_reached(position: Vector3)
signal aim_started
signal aim_ended
signal hook_fired
signal hook_attached(hook_position: Vector3)
signal hook_released
signal pole_grabbed(pole_position: Vector3)
signal pole_launched(launch_velocity: Vector3)
```

- [ ] **Step 2: Add layer 7 name to project.godot**

In `project.godot`, find the `[layer_names]` section and add:
```ini
3d_physics/layer_7="flex_poles"
```

After the existing `3d_physics/layer_6="interactables"` line.

- [ ] **Step 3: Commit**

```bash
git add Events.gd project.godot
git commit -m "feat: add flex_poles collision layer 7 and pole signals to Events"
```

---

## Task 2: Hook Crosshair — Core Logic

**Files:**
- Create: `Player/hook_crosshair.gd`

- [ ] **Step 1: Create hook_crosshair.gd**

This script scans for hookable targets each physics frame. It uses the camera's forward direction to find the best target by angular proximity. It exposes the current target and attach point for GrapplingHookArm to use.

```gdscript
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

	_camera = _player.get_node("%Camera3D") as Camera3D
	top_level = false

	_setup_detection_area()
	_setup_3d_indicator()
	_setup_2d_crosshair()


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

	# Evaluar todos los cuerpos/areas en rango
	var overlapping = _detection_area.get_overlapping_areas()
	for area in overlapping:
		var hookable = _get_hookable_parent(area)
		if not hookable:
			continue

		var point = _get_hook_point(area, hookable)
		var to_point = (point - cam_origin).normalized()
		var angle_deg = rad_to_deg(acos(clampf(cam_forward.dot(to_point), -1.0, 1.0)))

		if angle_deg < best_angle:
			# Verificar linea de vision (no bloqueado por mundo)
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
## el nodo hookable (HookRing, FlexPole, o JumpThruPlatform)
func _get_hookable_parent(area: Area3D) -> Node3D:
	var parent = area.get_parent()
	if parent is HookRing or parent is FlexPole:
		return parent
	# Para JumpThruPlatform, el area misma puede ser el nodo
	if area.get_parent() is JumpThruPlatform:
		return area.get_parent()
	# El area podria ser hija directa de un hookable
	if area is HookRing or area is FlexPole:
		return area
	return parent if parent and (parent.collision_layer & HOOKABLE_MASK) else null


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
```

- [ ] **Step 2: Verify file created**

Check that the file exists and has no syntax issues:
```bash
ls -la "Player/hook_crosshair.gd"
```

- [ ] **Step 3: Commit**

```bash
git add Player/hook_crosshair.gd
git commit -m "feat: add hook crosshair with angular priority target selection"
```

---

## Task 3: Integrate Crosshair with Player

**Files:**
- Modify: `Player/player_3dEdited1.gd:16-19` (add onready var)
- Modify: `Player/player_3dEdited1.gd:49-50` (setup in _ready)

The crosshair node must be added to the player scene in Godot editor. This task prepares the code reference.

- [ ] **Step 1: Add crosshair reference to player**

In `Player/player_3dEdited1.gd`, add a new `@onready` variable after the existing ones (after line 19):

```gdscript
# Find this line:
@onready var _arm_socket: ArmSocket = get_node_or_null("ArmSocket")

# Add after it:
@onready var _hook_crosshair: HookCrosshair = get_node_or_null("HookCrosshair")
```

- [ ] **Step 2: Note for Godot editor**

**MANUAL STEP IN GODOT EDITOR:**
1. Open `player_3d.tscn` (the player scene)
2. Add a child node of type `Node3D` to the Player root
3. Name it `HookCrosshair`
4. Assign script `res://Player/hook_crosshair.gd`

The script handles all child node creation programmatically (_setup_detection_area, _setup_3d_indicator, _setup_2d_crosshair), so no further scene configuration is needed.

- [ ] **Step 3: Commit code changes**

```bash
git add Player/player_3dEdited1.gd
git commit -m "feat: add hook crosshair reference to player controller"
```

---

## Task 4: Integrate Crosshair with GrapplingHookArm

**Files:**
- Modify: `Player/Arms/GrapplingHook/grappling_hook_arm.gd:53-93` (_fire_hook method)

The grappling hook arm currently does its own raycast to find the target point. We modify it to use the crosshair's target when available, falling back to the original raycast when no crosshair target exists.

- [ ] **Step 1: Add crosshair reference getter**

In `grappling_hook_arm.gd`, add a helper method to get the crosshair from the player. Add after the `get_charge_ratio()` method (after line 156):

```gdscript
## Obtiene el HookCrosshair del player (si existe)
func _get_crosshair() -> HookCrosshair:
	if player and player.has_node("HookCrosshair"):
		return player.get_node("HookCrosshair") as HookCrosshair
	return null
```

- [ ] **Step 2: Modify _fire_hook to use crosshair target**

Replace the `_fire_hook()` method (lines 53-93) with this version that checks the crosshair first:

```gdscript
func _fire_hook() -> void:
	if not player:
		_state = HookState.IDLE
		return

	# Calcular distancia segun carga (lerp entre min y max)
	var charge_ratio = clampf(_charge_timer / CHARGE_TIME, 0.0, 1.0)
	_current_max_distance = lerpf(HOOK_MIN_DISTANCE, HOOK_MAX_DISTANCE, charge_ratio)

	var target_point: Vector3
	var crosshair = _get_crosshair()

	if crosshair and crosshair.has_target:
		# Usar el target del crosshair (snap angular)
		target_point = crosshair.current_attach_point
		# Verificar que esta dentro de la distancia de carga
		var dist_to_target = player.global_position.distance_to(target_point)
		if dist_to_target > _current_max_distance:
			# Target fuera de rango de carga — fallback a raycast
			target_point = _raycast_target_point(charge_ratio)
	else:
		# Sin crosshair o sin target — raycast original
		target_point = _raycast_target_point(charge_ratio)

	# Direccion del disparo: desde la mano del player hacia el target point
	var hand_pos = _get_hand_position()
	var fire_dir = (target_point - hand_pos).normalized()

	_state = HookState.FLYING
	_projectile.fire(hand_pos, fire_dir, HOOK_SPEED, _current_max_distance)
	Events.hook_fired.emit()
	print("GrapplingHook: disparo (carga: %.0f%%, distancia: %.1f)" % [charge_ratio * 100, _current_max_distance])


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
```

- [ ] **Step 3: Detect FlexPole on hook hit**

Modify `_on_hook_hit()` (line 96) to differentiate between HookRing and FlexPole targets. Replace the method:

```gdscript
func _on_hook_hit(hit_position: Vector3, collider: Node) -> void:
	_state = HookState.ATTACHED
	_attach_point = hit_position
	_attached_collider = collider
	var rope_length = player.global_position.distance_to(_attach_point)

	# Detectar si el collider es un FlexPole
	var flex_pole = _find_flex_pole(collider)
	if flex_pole:
		Events.pole_grabbed.emit(hit_position)
		arm_state_changed.emit("FlexPoleHooked")
		print("GrapplingHook: enganchado a FlexPole en %s" % [hit_position])
	else:
		Events.hook_attached.emit(hit_position)
		arm_state_changed.emit("Hooked")
		print("GrapplingHook: enganchado en %s (distancia: %.1f)" % [hit_position, rope_length])


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
```

- [ ] **Step 4: Update collision mask in hook_projectile.gd**

In `hook_projectile.gd`, update the collision mask in `_physics_process` (line 55) to also detect flex_poles (layer 7 = bit 6):

```gdscript
# Find this line:
	query.collision_mask = 0b1101  # bits 0, 2, 3 = layers 1, 3, 4

# Replace with:
	query.collision_mask = 0b1001101  # bits 0, 2, 3, 6 = layers 1, 3, 4, 7
```

- [ ] **Step 5: Commit**

```bash
git add Player/Arms/GrapplingHook/grappling_hook_arm.gd Player/Arms/GrapplingHook/hook_projectile.gd
git commit -m "feat: integrate crosshair with grappling hook, detect FlexPole targets"
```

---

## Task 5: Flex Pole — Level Element

**Files:**
- Create: `Level/Elements/flex_pole.gd`

- [ ] **Step 1: Create flex_pole.gd**

The flex pole is a bendable pole that acts as a slingshot. It manages its own bend state and visual bending, and emits a signal when the player launches.

```gdscript
class_name FlexPole extends Node3D

## Palo flexible / arbol catapulta. El jugador se engancha con el hook,
## dobla el palo con input (S), orbita alrededor (A/D), y al saltar
## el palo lo catapulta en la direccion opuesta.
## Inspirado en la mecanica de Crimson Desert.

signal pole_launched(launch_velocity: Vector3)
signal pole_grabbed(by: CharacterBody3D)
signal pole_released()

enum PoleState { IDLE, BENDING, RELEASE, SPRINGING_BACK }

@export var max_bend_angle: float = 45.0       # Grados maximos de doblez
@export var bend_speed: float = 2.0            # Velocidad de doblez (bend_amount/sec)
@export var launch_force_min: float = 15.0     # Fuerza con doblez minimo
@export var launch_force_max: float = 35.0     # Fuerza con doblez maximo
@export var spring_back_speed: float = 8.0     # Velocidad de retorno a posicion original
@export var pole_height: float = 6.0           # Altura del palo

var _state := PoleState.IDLE
var bend_amount: float = 0.0  # 0.0 a 1.0 — cuanto esta doblado

var _pole_bend: Node3D       # Pivot de rotacion
var _pole_mesh: MeshInstance3D
var _pole_base: MeshInstance3D
var _hook_point: Area3D
var _bend_direction := Vector3.FORWARD  # Direccion en la que se dobla (hacia el jugador)


func _ready():
	_setup_visuals()
	_setup_hook_point()


func _setup_visuals():
	# Base fija del palo
	_pole_base = MeshInstance3D.new()
	_pole_base.name = "PoleBase"
	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = 0.2
	base_mesh.bottom_radius = 0.3
	base_mesh.height = 0.5
	_pole_base.mesh = base_mesh
	var base_mat = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.35, 0.22, 0.1)  # Marron oscuro
	_pole_base.material_override = base_mat
	_pole_base.position = Vector3(0, 0.25, 0)
	add_child(_pole_base)

	# Pivot de rotacion para el doblez
	_pole_bend = Node3D.new()
	_pole_bend.name = "PoleBend"
	_pole_bend.position = Vector3(0, 0.5, 0)  # Base del palo
	add_child(_pole_bend)

	# Palo visual (hijo del pivot)
	_pole_mesh = MeshInstance3D.new()
	_pole_mesh.name = "PoleMesh"
	var pole_mesh_res = CylinderMesh.new()
	pole_mesh_res.top_radius = 0.08
	pole_mesh_res.bottom_radius = 0.15
	pole_mesh_res.height = pole_height
	_pole_mesh.mesh = pole_mesh_res
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.45, 0.3, 0.12)  # Marron claro
	_pole_mesh.material_override = pole_mat
	# Centrar el mesh para que la base quede en el pivot
	_pole_mesh.position = Vector3(0, pole_height * 0.5, 0)
	_pole_bend.add_child(_pole_mesh)


func _setup_hook_point():
	_hook_point = Area3D.new()
	_hook_point.name = "HookPoint"
	# Layer 7 (flex_poles) = bit 6 = valor 64
	_hook_point.collision_layer = 64
	_hook_point.collision_mask = 0
	_hook_point.monitorable = true
	_hook_point.monitoring = false

	var shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.8  # Area de enganche generosa
	shape.shape = sphere
	_hook_point.add_child(shape)
	# Posicionar en la punta del palo
	_hook_point.position = Vector3(0, 0.5 + pole_height * 0.85, 0)
	add_child(_hook_point)


## Posicion global del punto de enganche (para el crosshair)
func get_hook_point_position() -> Vector3:
	if _hook_point:
		return _hook_point.global_position
	return global_position + Vector3.UP * pole_height


## Llamado por FlexPoleState cuando el jugador se engancha
func grab(player: CharacterBody3D) -> void:
	_state = PoleState.BENDING
	bend_amount = 0.0
	pole_grabbed.emit(player)


## Llamado por FlexPoleState para actualizar el doblez (cada frame)
func update_bend(amount: float, player_direction: Vector3) -> void:
	bend_amount = clampf(amount, 0.0, 1.0)
	_bend_direction = player_direction.normalized()
	_apply_visual_bend()


## Calcula y retorna la velocidad de lanzamiento
func calculate_launch_velocity(player_position: Vector3) -> Vector3:
	var pole_pos = global_position
	# Direccion: opuesta a donde esta el jugador respecto al palo
	var launch_dir = (pole_pos - player_position).normalized()
	# Siempre componente vertical fuerte
	launch_dir.y = maxf(launch_dir.y, 0.4)
	launch_dir = launch_dir.normalized()

	var force = lerpf(launch_force_min, launch_force_max, bend_amount)
	return launch_dir * force


## Llamado cuando el jugador salta/suelta — inicia el lanzamiento
func release() -> void:
	_state = PoleState.SPRINGING_BACK
	pole_released.emit()


func _physics_process(delta: float):
	match _state:
		PoleState.SPRINGING_BACK:
			bend_amount = move_toward(bend_amount, 0.0, spring_back_speed * delta)
			_apply_visual_bend()
			if bend_amount <= 0.01:
				bend_amount = 0.0
				_state = PoleState.IDLE
				_pole_bend.rotation = Vector3.ZERO


func _apply_visual_bend():
	if not _pole_bend:
		return
	# Rotar el pivot en la direccion del doblez
	var bend_angle_rad = deg_to_rad(max_bend_angle * bend_amount)
	# Calcular el eje de rotacion perpendicular a la direccion del doblez
	var bend_2d = Vector2(_bend_direction.x, _bend_direction.z).normalized()
	# El palo se dobla HACIA el jugador, asi que rotamos en el eje perpendicular
	_pole_bend.rotation = Vector3(
		bend_2d.y * bend_angle_rad,   # Rotation X = componente Z de la direccion
		0.0,
		-bend_2d.x * bend_angle_rad   # Rotation Z = componente X negado
	)
```

- [ ] **Step 2: Commit**

```bash
git add Level/Elements/flex_pole.gd
git commit -m "feat: add FlexPole level element with bend and launch mechanics"
```

---

## Task 6: Flex Pole Scene

**Files:**
- Create: `Level/Elements/flex_pole.tscn`

This is a minimal scene wrapper. Most of the node tree is created programmatically in `flex_pole.gd._ready()`, but having a `.tscn` makes it easy to drag-and-drop into levels from the Godot editor.

- [ ] **Step 1: Create the scene file**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" uid="uid://flex_pole_script" path="res://Level/Elements/flex_pole.gd" id="1_fp"]

[node name="FlexPole" type="Node3D"]
script = ExtResource("1_fp")
```

**NOTE:** The UID will need to be regenerated by Godot. The simplest approach:

**MANUAL STEP IN GODOT EDITOR:**
1. Create a new Scene → Root node: Node3D
2. Name it `FlexPole`
3. Assign script `res://Level/Elements/flex_pole.gd`
4. Save as `res://Level/Elements/flex_pole.tscn`

The script creates all child nodes (PoleBase, PoleBend, PoleMesh, HookPoint) programmatically in `_ready()`.

- [ ] **Step 2: Commit**

```bash
git add Level/Elements/flex_pole.tscn
git commit -m "feat: add FlexPole scene for editor instancing"
```

---

## Task 7: FlexPoleState — Player State

**Files:**
- Create: `Player/States/flex_pole_state.gd`

- [ ] **Step 1: Create flex_pole_state.gd**

Dedicated player state for when attached to a flex pole. The player orbits around the pole (A/D), bends it (S), reduces bend (W), and launches on jump.

```gdscript
class_name FlexPoleState extends State

## Estado del jugador cuando esta enganchado a un FlexPole.
## S = doblar (aumentar potencia), W = reducir doblez,
## A/D = orbitar alrededor del palo (cambiar direccion de lanzamiento),
## Jump = catapulta. Sin gravedad de pendulo — el jugador esta pegado al palo.

const ORBIT_SPEED := 3.0          # Velocidad de orbita alrededor del palo (rad/sec)
const ORBIT_RADIUS := 2.0         # Distancia del jugador al palo
const BEND_SPEED := 2.0           # Velocidad de doblez con S
const UNBEND_SPEED := 1.5         # Velocidad de reduccion con W
const ATTACHED_HEIGHT_RATIO := 0.7  # Altura del jugador relativa al palo (0-1)

var player: CharacterBody3D
var _flex_pole: FlexPole = null
var _orbit_angle: float = 0.0     # Angulo actual alrededor del palo (radianes)
var _bend_amount: float = 0.0


func enter(params := {}):
	if not player:
		player = state_machine.get_parent()

	_flex_pole = params.get("flex_pole", null)
	if not _flex_pole:
		push_warning("FlexPoleState: no flex_pole in params, returning to Airborne")
		state_machine.transition_to("Airborne")
		return

	_bend_amount = 0.0

	# Calcular angulo orbital inicial basado en posicion actual del jugador
	var to_player = player.global_position - _flex_pole.global_position
	_orbit_angle = atan2(to_player.x, to_player.z)

	# Posicionar jugador en el punto orbital
	_update_player_position()

	# Notificar al pole que fue agarrado
	_flex_pole.grab(player)

	# Detener velocidad
	player.velocity = Vector3.ZERO

	# Animacion de colgado
	player._skin.fall()

	# Camara
	player._target_camera_distance = 5.0
	player._target_camera_fov = 80.0


func exit():
	if _flex_pole:
		_flex_pole.release()
		_flex_pole = null
	_bend_amount = 0.0

	# Restaurar camara
	player._target_camera_distance = player.camera_default_distance
	player._target_camera_fov = player.camera_default_fov


func process_physics(delta: float):
	if not _flex_pole:
		state_machine.transition_to("Airborne")
		return

	var move_dir = player.get_move_direction()
	var input_raw = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# --- ORBITAR (A/D) ---
	# Usar input raw para no depender de la camara en eje lateral
	if abs(input_raw.x) > 0.1:
		_orbit_angle -= input_raw.x * ORBIT_SPEED * delta

	# --- DOBLAR (S = back = input_raw.y positivo en Godot) ---
	if input_raw.y > 0.1:
		_bend_amount = minf(_bend_amount + BEND_SPEED * delta, 1.0)
	# --- REDUCIR DOBLEZ (W = forward = input_raw.y negativo) ---
	elif input_raw.y < -0.1:
		_bend_amount = maxf(_bend_amount - UNBEND_SPEED * delta, 0.0)

	# Actualizar posicion del jugador en la orbita
	_update_player_position()

	# Actualizar el doblez visual del palo
	var player_dir = (player.global_position - _flex_pole.global_position).normalized()
	_flex_pole.update_bend(_bend_amount, player_dir)

	# Rotar skin hacia el palo
	var look_dir = (_flex_pole.global_position - player.global_position)
	look_dir.y = 0.0
	if look_dir.length() > 0.1:
		var target_angle = Vector3.BACK.signed_angle_to(look_dir.normalized(), Vector3.UP)
		player._skin.global_rotation.y = lerp_angle(
			player._skin.global_rotation.y, target_angle, 10.0 * delta
		)

	# No llamar move_and_slide — el jugador esta fijo en posicion orbital
	# (move_and_slide resetea is_on_floor, no queremos eso)

	# --- TRANSICIONES ---

	# Saltar = catapulta
	if player.jump_buffer_timer > 0.0:
		player.jump_buffer_timer = 0.0
		var launch_vel = _flex_pole.calculate_launch_velocity(player.global_position)
		player.velocity = launch_vel
		Events.pole_launched.emit(launch_vel)
		player.apply_squash_and_stretch(Vector3(0.7, 1.4, 0.7))
		_notify_arm_release()
		state_machine.transition_to("Airborne", {"jumped": true, "boosted": true})
		return

	# Soltar hook (click) = soltar sin catapulta
	if Input.is_action_just_pressed("left_click"):
		_notify_arm_release()
		state_machine.transition_to("Airborne")
		return


func _update_player_position():
	if not _flex_pole:
		return
	var pole_pos = _flex_pole.global_position
	var height = _flex_pole.pole_height * ATTACHED_HEIGHT_RATIO

	# Calcular posicion orbital
	var offset = Vector3(
		sin(_orbit_angle) * ORBIT_RADIUS,
		height,
		cos(_orbit_angle) * ORBIT_RADIUS
	)

	# Cuando el palo se dobla, el jugador baja un poco
	offset.y -= _bend_amount * 2.0

	player.global_position = pole_pos + offset


## Notifica al brazo que se solto el gancho
func _notify_arm_release():
	if player._arm_socket and player._arm_socket.current_arm:
		var arm = player._arm_socket.current_arm
		if arm.has_method("cancel_hook"):
			arm.cancel_hook()
```

- [ ] **Step 2: Commit**

```bash
git add Player/States/flex_pole_state.gd
git commit -m "feat: add FlexPoleState with orbit, bend, and launch mechanics"
```

---

## Task 8: Integrate FlexPoleState with Player

**Files:**
- Modify: `Player/player_3dEdited1.gd:122-129` (_on_arm_state_changed)

- [ ] **Step 1: Add FlexPoleHooked case to _on_arm_state_changed**

In `Player/player_3dEdited1.gd`, find the `_on_arm_state_changed` method (line 122). Add the new case for `"FlexPoleHooked"` between the existing `"Hooked"` and `"Released"` cases:

```gdscript
# Find this block:
func _on_arm_state_changed(new_state: String) -> void:
	match new_state:
		"Hooked":
			if _arm_socket and _arm_socket.current_arm:
				var arm = _arm_socket.current_arm
				var attach_point = arm.get_attach_point() if arm.has_method("get_attach_point") else Vector3.ZERO
				var rope_length = arm.get_rope_length() if arm.has_method("get_rope_length") else 5.0
				if _state_machine:
					_state_machine.transition_to("Hooked", {
						"attach_point": attach_point,
						"rope_length": rope_length
					})
		"Released":
			if _state_machine and _state_machine.current_state and _state_machine.current_state.name == "Hooked":
				_state_machine.transition_to("Airborne")

# Replace with:
func _on_arm_state_changed(new_state: String) -> void:
	match new_state:
		"Hooked":
			if _arm_socket and _arm_socket.current_arm:
				var arm = _arm_socket.current_arm
				var attach_point = arm.get_attach_point() if arm.has_method("get_attach_point") else Vector3.ZERO
				var rope_length = arm.get_rope_length() if arm.has_method("get_rope_length") else 5.0
				if _state_machine:
					_state_machine.transition_to("Hooked", {
						"attach_point": attach_point,
						"rope_length": rope_length
					})
		"FlexPoleHooked":
			if _arm_socket and _arm_socket.current_arm:
				var arm = _arm_socket.current_arm
				var attached_collider = arm._attached_collider if arm.get("_attached_collider") else null
				var flex_pole = _find_flex_pole_from_collider(attached_collider)
				if flex_pole and _state_machine:
					_state_machine.transition_to("FlexPole", {
						"flex_pole": flex_pole
					})
		"Released":
			if _state_machine and _state_machine.current_state:
				var state_name = _state_machine.current_state.name
				if state_name == "Hooked" or state_name == "FlexPole":
					_state_machine.transition_to("Airborne")
```

- [ ] **Step 2: Add helper method to find FlexPole from collider**

Add this method to `player_3dEdited1.gd`, after the `_on_arm_state_changed` method (after the replaced block):

```gdscript
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
```

- [ ] **Step 3: Note for Godot editor — add FlexPole state node**

**MANUAL STEP IN GODOT EDITOR:**
1. Open `player_3d.tscn`
2. Under `PlayerStateMachine`, add a child node of type `Node`
3. Name it `FlexPole`
4. Assign script `res://Player/States/flex_pole_state.gd`

Without this node, the state machine won't find the state and will print a warning.

- [ ] **Step 4: Commit**

```bash
git add Player/player_3dEdited1.gd
git commit -m "feat: integrate FlexPoleState with player arm state signals"
```

---

## Task 9: Test Level — Hub Central + Zona 1 (Swing Básico)

**Files:**
- Modify: `Level/test_level.tscn` (via Godot editor)

This task and the following ones describe the level geometry to build in the Godot editor. Since `.tscn` files with many nodes are best edited visually, these are structured as editor instructions.

- [ ] **Step 1: Build Hub Central**

**In Godot editor, in test_level.tscn:**

Create a parent `Node3D` named `Hub` at position `(0, 0, 0)`:
- **Floor:** `StaticBody3D` + `MeshInstance3D` (BoxMesh 20x1x20) + `CollisionShape3D` (BoxShape3D 20x1x20) at `(0, -0.5, 0)`
- **Checkpoint:** Instance `checkpoint.tscn` at `(0, 0, 0)`
- Material: Use a distinct color (e.g., light blue) so the hub is visually identifiable

Create 4 ramp/corridor `StaticBody3D` connecting the hub to each zone direction:
- North corridor: BoxShape3D (4x1x10) at `(0, -0.5, -15)` → leads to Zone 1
- East corridor: BoxShape3D (10x1x4) at `(15, -0.5, 0)` → leads to Zone 2
- West corridor: BoxShape3D (10x1x4) at `(-15, -0.5, 0)` → leads to Zone 3
- South corridor: BoxShape3D (4x1x10) at `(0, -0.5, 15)` → leads to Zone 4

- [ ] **Step 2: Build Zona 1 — Swing Básico (Norte)**

Create a parent `Node3D` named `Zone1_Swing` at `(0, 0, -30)`:

**Platforms (StaticBody3D + BoxShape3D):**
- Start platform: 6x1x6 at `(0, 0, 0)` — first landing after corridor
- Mid platform 1: 4x1x4 at `(0, 2, -12)` — after first swing
- Mid platform 2: 4x1x4 at `(0, 4, -24)` — after second swing
- End platform: 6x1x6 at `(0, 6, -38)` — final landing

**Hook Rings (instance hook_ring.tscn or create HookRing nodes):**
- Ring 1: at `(0, 8, -6)` — between start and mid1 (5m gap)
- Ring 2: at `(0, 10, -18)` — between mid1 and mid2 (8m gap)
- Ring 3: at `(0, 12, -31)` — between mid2 and end (12m gap)

**Checkpoint:** Instance at Zone1 start platform

**Kill plane note:** The global KillPlane at y=-33 already covers this zone.

- [ ] **Step 3: Verify in editor**

Run the scene and test:
1. Walk from hub to Zone 1
2. Crosshair should highlight hook rings when looking at them
3. Hook should fire to the crosshair target
4. Swing between platforms

- [ ] **Step 4: Commit**

```bash
git add Level/test_level.tscn
git commit -m "feat: add hub central and Zone 1 (swing basico) to test level"
```

---

## Task 10: Test Level — Zona 2 (Flex Poles, Este)

**Files:**
- Modify: `Level/test_level.tscn` (via Godot editor)

- [ ] **Step 1: Build Zona 2 — Flex Poles**

Create a parent `Node3D` named `Zone2_FlexPoles` at `(30, 0, 0)`:

**Ground floor:** StaticBody3D + BoxShape3D 30x1x30 at `(0, -0.5, 0)` — large flat area for testing orbiting

**Flex Poles (instance flex_pole.tscn):**
- Pole 1 (low): at `(0, 0, -5)` with `pole_height=4`, `launch_force_max=20` — short, gentle launch
- Pole 2 (medium): at `(8, 0, 0)` with `pole_height=6`, `launch_force_max=30` — default
- Pole 3 (tall): at `(-5, 0, 8)` with `pole_height=8`, `launch_force_max=40` — powerful launch

**Target platforms (StaticBody3D + BoxShape3D) — landing targets at heights:**
- Low target: 4x1x4 at `(0, 6, -12)` — reachable from Pole 1
- Medium target: 4x1x4 at `(14, 10, 0)` — reachable from Pole 2
- High target: 4x1x4 at `(-5, 15, 16)` — reachable from Pole 3
- Bonus far target: 3x1x3 at `(20, 8, 10)` — requires full bend + good angle

**Checkpoint:** Instance at zone entrance

- [ ] **Step 2: Verify in editor**

Run and test:
1. Walk from hub to Zone 2
2. Crosshair should highlight flex pole hook points
3. Hook onto each pole, orbit around it, bend with S, launch with jump
4. Try to reach each target platform

- [ ] **Step 3: Commit**

```bash
git add Level/test_level.tscn
git commit -m "feat: add Zone 2 (flex poles) to test level"
```

---

## Task 11: Test Level — Zona 3 (Swing Encadenado, Oeste)

**Files:**
- Modify: `Level/test_level.tscn` (via Godot editor)

- [ ] **Step 1: Build Zona 3 — Swing Encadenado**

Create a parent `Node3D` named `Zone3_ChainSwing` at `(-30, 0, 0)`:

**Start platform:** StaticBody3D + BoxShape3D 6x1x6 at `(0, 0, 0)`

**Hook Rings in zigzag pattern (no floor between them):**
- Ring 1: at `(-4, 10, -6)`
- Ring 2: at `(4, 12, -14)`
- Ring 3: at `(-4, 11, -22)`
- Ring 4: at `(4, 13, -30)`
- Ring 5: at `(-4, 12, -38)`
- Ring 6: at `(4, 14, -46)`

**End platform:** StaticBody3D + BoxShape3D 6x1x6 at `(0, 2, -52)`

**Checkpoint:** Instance at start platform

No intermediate platforms — the player must chain swings without landing. The zigzag pattern forces releasing and re-hooking at angles, testing momentum conservation and crosshair tracking while moving.

- [ ] **Step 2: Verify in editor**

Run and test:
1. Walk from hub to Zone 3
2. Swing from ring to ring without touching the ground
3. Crosshair should track next ring while swinging
4. Momentum should carry between swings

- [ ] **Step 3: Commit**

```bash
git add Level/test_level.tscn
git commit -m "feat: add Zone 3 (chain swing) to test level"
```

---

## Task 12: Test Level — Zona 4 (Combo / Flow, Sur)

**Files:**
- Modify: `Level/test_level.tscn` (via Godot editor)

- [ ] **Step 1: Build Zona 4 — Combo**

Create a parent `Node3D` named `Zone4_Combo` at `(0, 0, 30)`:

**Linear sequence — each section leads to the next:**

**Section A: Platform start**
- Start platform: StaticBody3D 6x1x6 at `(0, 0, 0)`
- Checkpoint at start

**Section B: Hook ring swing**
- Hook Ring at `(0, 8, 8)`
- Landing platform: 4x1x4 at `(0, 2, 16)` — land after swing

**Section C: Flex pole catapult**
- FlexPole at `(0, 2, 20)` with `pole_height=6`, `launch_force_max=35`
- Target platform (high): 5x1x5 at `(0, 14, 28)` — land after catapult

**Section D: Slide section**
- Ramp down from high platform: BoxShape3D 4x1x12 rotated -30deg X at `(0, 8, 34)`
- Flat for slide: BoxShape3D 8x1x10 at `(0, 2, 42)`

**Section E: Hook to finish**
- Hook Ring at `(0, 10, 48)`
- End platform: 6x1x6 at `(0, 4, 55)`

This creates a flow: platform → swing → land → pole catapult → land high → slide down ramp → hook → finish.

- [ ] **Step 2: Verify full flow**

Run and test the complete loop:
1. Hub → Zone 4
2. Swing across gap
3. Hook to flex pole, catapult up
4. Land on high platform, slide down ramp
5. Hook to final ring, land on end platform

- [ ] **Step 3: Commit**

```bash
git add Level/test_level.tscn
git commit -m "feat: add Zone 4 (combo flow) to test level"
```

---

## Task 13: Final Verification & Polish

- [ ] **Step 1: Run full playthrough**

Test all systems together:
1. **Crosshair:** Shows green on valid targets, gray when nothing in range. Tracks correctly while moving.
2. **Hook firing:** Uses crosshair target when available. Falls back to raycast.
3. **Flex Pole grab:** Hooking onto a flex pole enters FlexPoleState (not HookedState).
4. **Flex Pole orbit:** A/D orbits player around pole. Visual rotation of pole skin follows.
5. **Flex Pole bend:** S increases bend. W decreases. Visual bending matches.
6. **Flex Pole launch:** Jump catapults player. Direction matches orbit position. Force matches bend amount.
7. **Zone transitions:** Can walk between hub and all zones.
8. **Checkpoints:** Each zone has a checkpoint. Respawn works.

- [ ] **Step 2: Adjust parameters if needed**

Common tuning points:
- `HookCrosshair.MAX_ANGLE_DEG` — if crosshair snaps to wrong targets, reduce (try 20)
- `FlexPole.launch_force_max` — if launches feel too weak/strong, adjust per pole
- `FlexPoleState.ORBIT_SPEED` — if orbiting feels sluggish, increase (try 4.0)
- `FlexPoleState.ORBIT_RADIUS` — if player clips into pole, increase (try 2.5)
- Hook ring positions in zones — if swings feel too easy/hard, adjust heights and distances

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete hook crosshair, flex pole, and modular test level"
```
