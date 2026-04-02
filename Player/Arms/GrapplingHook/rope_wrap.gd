class_name RopeWrap extends RefCounted

## Sistema de wrapping multi-segmento para la cuerda del grappling hook.
## La cuerda se curva alrededor de objetos creando wrap points en los bordes
## de geometria que obstruyen la linea directa entre el jugador y el enganche.
## El jugador balancea desde el ultimo wrap point, no desde el enganche original.
##
## Uso tipico (desde hooked_state.gd):
##   rope_wrap.initialize(attach_point, player.global_position)
##   rope_wrap.update(player.global_position, space_state, player.get_rid())
##   var pivot := rope_wrap.get_active_pivot()
##   var length := rope_wrap.get_effective_rope_length()

const WRAP_OFFSET := 0.05        # Offset del wrap point desde la superficie para evitar z-fighting
const UNWRAP_ANGLE_DEG := 5.0    # Tolerancia de angulo para detectar unwrap
const NO_HOOK_BITMASK := 128     # Layer 8 = no_hook (bit 7)

## Array de puntos de anclaje: [hook_point, wrap1, wrap2, ...]
## El primero siempre es el punto de enganche original.
## Los siguientes son wrap points intermedios creados por colision.
var wrap_points: Array[Vector3] = []

## Largo total de la cuerda, calculado en initialize() y fijo desde entonces.
## Los estados la pueden modificar via climb (acortar/alargar).
var total_rope_length: float = 0.0


## Inicializa el sistema con el punto de enganche y la posicion del jugador.
## Debe llamarse una vez cuando el gancho se engancha.
func initialize(hook_point: Vector3, player_pos: Vector3) -> void:
	wrap_points.clear()
	wrap_points.append(hook_point)
	total_rope_length = hook_point.distance_to(player_pos)


## Actualiza el sistema cada frame de fisica.
## Detecta nuevos wraps (geometria obstaculizando la cuerda) y unwraps (camino libre).
## Llamar desde hooked_state.process_physics() con el space state del mundo.
func update(player_pos: Vector3, space: PhysicsDirectSpaceState3D, player_rid: RID) -> void:
	# Primero intentar unwrap (tiene prioridad: si el camino se despejo, simplificar)
	_check_unwrap(player_pos, space, player_rid)
	# Luego verificar si hay nueva geometria bloqueando
	_check_wrap(player_pos, space, player_rid)


## Retorna el ultimo wrap point, que es el pivote activo del pendulo.
## Si no hay wraps, retorna el punto de enganche original.
func get_active_pivot() -> Vector3:
	if wrap_points.is_empty():
		return Vector3.ZERO
	return wrap_points[-1]


## Retorna el largo efectivo de cuerda disponible para el ultimo segmento (jugador <-> pivot).
## = largo total - suma de segmentos fijos entre wrap points.
## Clampeado a un minimo de 1.0 para evitar degeneracion.
func get_effective_rope_length() -> float:
	var fixed := _get_fixed_segments_length()
	return maxf(total_rope_length - fixed, 1.0)


## Retorna todos los puntos de la cuerda incluyendo la posicion del jugador al final.
## Util para que RopeVisual dibuje la cuerda multi-segmento.
func get_all_points(player_pos: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for p in wrap_points:
		points.append(p)
	points.append(player_pos)
	return points


# ---------------------------------------------------------------------------
# Logica interna
# ---------------------------------------------------------------------------

## Verifica si hay nueva geometria bloqueando la linea directa jugador <-> pivot actual.
## Si hay impacto, inserta un nuevo wrap point en el borde de la superficie.
func _check_wrap(player_pos: Vector3, space: PhysicsDirectSpaceState3D, player_rid: RID) -> void:
	if wrap_points.is_empty():
		return

	var pivot := wrap_points[-1]

	var query := PhysicsRayQueryParameters3D.create(player_pos, pivot)
	# Solo layer 1 (world geometry). Excluir layer 8 (no_hook) via filtrado manual.
	query.collision_mask = 1  # Solo layer 1 (bit 0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [player_rid]

	var result := space.intersect_ray(query)
	if not result:
		return

	# Filtrar superficies marcadas como no_hook (layer 8)
	var collider = result.get("collider")
	if collider is CollisionObject3D and (collider.collision_layer & NO_HOOK_BITMASK):
		return

	# Nuevo wrap point: ligeramente alejado de la superficie para evitar penetracion
	var normal: Vector3 = result.get("normal", Vector3.UP)
	var hit_pos: Vector3 = result["position"]
	var new_wrap_point: Vector3 = hit_pos + normal * WRAP_OFFSET
	wrap_points.append(new_wrap_point)


## Verifica si el pivot actual ya no es necesario porque hay linea libre hacia el anterior.
## Si el camino esta despejado, elimina el ultimo wrap point (unwrap natural al girar).
func _check_unwrap(player_pos: Vector3, space: PhysicsDirectSpaceState3D, player_rid: RID) -> void:
	# Necesitamos al menos: [hook_point, wrap1] para poder desenrollar wrap1
	if wrap_points.size() < 2:
		return

	# Intentar llegar al penultimo punto saltando el ultimo (el pivot actual)
	var second_to_last := wrap_points[-2]

	var query := PhysicsRayQueryParameters3D.create(player_pos, second_to_last)
	query.collision_mask = 1  # Solo layer 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [player_rid]

	var result := space.intersect_ray(query)
	if result:
		# Hay geometria bloqueando: el wrap point actual sigue siendo necesario
		return

	# Camino libre: el pivot actual ya no es necesario, desenrollar
	wrap_points.remove_at(wrap_points.size() - 1)


## Calcula la suma de longitudes de los segmentos fijos (entre wrap points consecutivos).
## Excluye el segmento final jugador <-> ultimo pivot (ese es el segmento activo/variable).
func _get_fixed_segments_length() -> float:
	var total := 0.0
	# Los segmentos fijos son entre wrap_points[0..n-1] (sin incluir el segmento al jugador)
	for i in range(wrap_points.size() - 1):
		total += wrap_points[i].distance_to(wrap_points[i + 1])
	return total
