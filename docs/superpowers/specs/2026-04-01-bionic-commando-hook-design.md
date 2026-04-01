# Bionic Commando Hook System Design

**Fecha:** 2026-04-01
**Estado:** Aprobado
**Branch:** `feature/bionic-commando-hook`

---

## 1. Crosshair Universal

### Objetivo
El crosshair pasa de detectar solo puntos específicos (hook rings, flex poles) a detectar **cualquier superficie enganchable** del mundo.

### Detección dual
1. **Raycast principal** desde el centro de la cámara cada physics frame
   - Detecta: layer 1 (world), layer 3 (jump-thru), layer 4 (hook rings), layer 7 (flex poles)
   - Excluye: layer 8 (`no_hook`), layer 2 (player)
   - Rango: `hook_max_distance` (20m)
   - Retorna: hit_point, hit_normal, hit_collider

2. **Snap angular** activo solo para objetos pequeños (hook rings, flex poles)
   - Cono de 30° desde el centro de la cámara
   - Si hay un hook ring o flex pole en el cono Y en rango → prioridad sobre superficie genérica
   - Usa el sistema actual de `Area3D.get_overlapping_areas()`

### Prioridad de selección
1. Hook ring o flex pole en cono angular (snap) → máxima prioridad
2. Superficie genérica por raycast → si no hay snap target

### Indicador visual
- **Verde** = superficie enganchable, indicador 3D en el hit point
- **Gris** = nada en rango o superficie no-hookable
- Hook rings y flex poles siguen mostrando el torus indicator

### Datos expuestos
```gdscript
var current_target: Node3D       # El nodo hookable (o null)
var current_attach_point: Vector3 # Punto exacto de enganche
var current_surface_normal: Vector3  # Normal de la superficie (NUEVO)
var has_target: bool
var is_special_target: bool      # True si es hook ring o flex pole (snap)
```

### Archivo
- Modificar: `Player/hook_crosshair.gd`

---

## 2. Enganche a Superficies — Comportamiento por Ángulo

### Objetivo
El hook se puede enganchar a cualquier superficie sólida. El comportamiento cambia según la orientación de la superficie.

### Clasificación por normal
| Normal de superficie | Condición | Comportamiento |
|---------------------|-----------|----------------|
| Techo / overhang | `normal.y < -0.3` | **Péndulo** — swing, gravedad, control aéreo mínimo |
| Pared | `abs(normal.y) <= 0.3` | **Recoil** — atrae al jugador hacia el punto a velocidad constante (25 u/s) |
| Piso / rampa | `normal.y > 0.3` | **Fast pull** — atrae al jugador hacia abajo más rápido que la gravedad normal |

### Integración con HookedState
- `hooked_state.gd` recibe `surface_normal: Vector3` en los params de `enter()`
- Según la normal, ejecuta una de las tres físicas
- Para hook rings y flex poles: siempre péndulo (normal no aplica)
- El tipo de enganche se determina una vez al entrar al estado

### Parámetros
```gdscript
const WALL_RECOIL_SPEED := 25.0      # Velocidad de atracción hacia paredes
const FLOOR_PULL_SPEED := 40.0       # Velocidad de atracción hacia piso
const FLOOR_PULL_GRAVITY_MULT := 2.5 # Multiplicador de gravedad para fast pull
```

### Transiciones
- **Péndulo (techo):** Sale con jump, click, o tocar suelo (igual que ahora)
- **Recoil (pared):** Sale al llegar al punto de enganche → Airborne, o con jump
- **Fast pull (piso):** Sale al llegar al punto → aterriza, o con jump

### Archivo
- Modificar: `Player/States/hooked_state.gd`

---

## 3. Rope Wrapping (Multi-segmento)

### Objetivo
La cuerda se curva alrededor de objetos creando nuevos puntos de pivote. El jugador balancea desde el último wrap point, no desde el enganche original. Estilo Worms Armageddon / Bionic Commando.

### Estructura de datos
```gdscript
# Lista ordenada de puntos: [hook_point, wrap1, wrap2, ..., player_pos]
var wrap_points: Array[Vector3] = []
var total_rope_length: float = 0.0  # Largo total constante
```

### Algoritmo de wrapping
Cada physics frame:

**1. Detección de wrap (nuevo obstáculo):**
- Raycast desde player hasta el último wrap point (penúltimo en la lista)
- Si hay hit con world geometry → insertar nuevo wrap point en la posición del hit
- El nuevo wrap point se convierte en el pivot activo

**2. Detección de unwrap (obstáculo ya no está en el camino):**
- Chequear si el ángulo entre los últimos 3 puntos se "desdobló"
- Si el segmento player→wrap_n→wrap_n-1 ya no tiene obstáculo en el medio → remover wrap_n
- Esto permite que la cuerda se "suelte" de esquinas cuando el jugador pasa al otro lado

**3. Constraint de cuerda:**
- El largo total de la cuerda (suma de todos los segmentos) se mantiene constante
- Solo el último segmento (último wrap point → player) es flexible
- El radio de péndulo efectivo = largo total - largo de segmentos fijos

### Wrap point placement
- El wrap point se coloca en el **edge/esquina** del objeto más cercano al hit
- Offset pequeño (0.05m) desde la superficie para evitar z-fighting y penetración

### Archivos
- Crear: `Player/Arms/GrapplingHook/rope_wrap.gd` — lógica de wrap/unwrap
- Modificar: `Player/Arms/GrapplingHook/rope_visual.gd` — renderizar N segmentos
- Modificar: `Player/States/hooked_state.gd` — usar último wrap point como pivot de péndulo

### rope_wrap.gd — Interfaz pública
```gdscript
class_name RopeWrap extends RefCounted

var wrap_points: Array[Vector3] = []  # [hook_point, ...wraps..., player_pos]
var total_rope_length: float = 0.0

func initialize(hook_point: Vector3, player_pos: Vector3) -> void
func update(player_pos: Vector3, space: PhysicsDirectSpaceState3D) -> void
func get_active_pivot() -> Vector3          # Último wrap point (pivot actual)
func get_effective_rope_length() -> float   # Largo del último segmento
func get_all_points() -> Array[Vector3]     # Para renderizar
```

---

## 4. No-Hook Zones

### Objetivo
Poder marcar superficies individuales como no-enganchables para diseño de niveles.

### Implementación
- Nuevo collision layer 8 = `no_hook`
- Cualquier `StaticBody3D` con layer 8 activo es ignorado por:
  - El raycast del crosshair
  - El raycast del hook projectile
  - El raycast de wrap detection
- Para marcar una superficie: activar layer 8 en el inspector de Godot

### Masks actualizadas
```
Crosshair raycast mask: layers 1,3,4,7 EXCLUYENDO layer 8
Hook projectile mask: layers 1,3,4,7 EXCLUYENDO layer 8
Wrap detection mask: layer 1 EXCLUYENDO layer 8
```

En la práctica: el mask es `0b1001101` (layers 1,3,4,7) y se excluyen los colliders que tengan layer 8 activo (bit 7 = 128). O alternativamente, las superficies no-hookables solo tienen layer 8 y no layer 1, así el mask normal ya las excluye.

**Enfoque recomendado:** Las superficies no-hookables mantienen layer 1 (para colisión normal del jugador) Y agregan layer 8. El crosshair/projectile/wrap chequean el hit y descartan si `collider.collision_layer & 128 != 0`.

### Archivo
- Modificar: `project.godot` — agregar nombre layer 8
- Modificar: `hook_crosshair.gd` — filtrar no_hook
- Modificar: `hook_projectile.gd` — filtrar no_hook
- Modificar: `rope_wrap.gd` — filtrar no_hook

---

## 5. Cambios al GrapplingHookArm

### Objetivo
El hook ahora dispara a cualquier superficie, no solo a hook rings y flex poles. Necesita pasar la `surface_normal` al player para que el HookedState sepa qué física usar.

### Cambios en _on_hook_hit
```gdscript
# Además de detectar FlexPole, ahora pasa surface_normal
# Para superficies genéricas: emite "Hooked" con normal
# Para flex poles: emite "FlexPoleHooked" (sin cambios)
# Para hook rings: emite "Hooked" con normal = Vector3.DOWN (siempre péndulo)
```

### Cambios en hook_projectile
- Almacenar `hit_normal` del resultado del raycast
- Exponerlo via getter para que grappling_hook_arm lo lea

### Archivos
- Modificar: `Player/Arms/GrapplingHook/grappling_hook_arm.gd`
- Modificar: `Player/Arms/GrapplingHook/hook_projectile.gd`

---

## 6. Resumen de Archivos

### Nuevos
| Archivo | Responsabilidad |
|---------|----------------|
| `Player/Arms/GrapplingHook/rope_wrap.gd` | Lógica de wrap/unwrap multi-segmento |

### Modificados
| Archivo | Cambios |
|---------|---------|
| `Player/hook_crosshair.gd` | Raycast universal + snap para objetos chicos + surface_normal |
| `Player/States/hooked_state.gd` | 3 comportamientos por normal (péndulo/recoil/pull) + integración con rope_wrap |
| `Player/Arms/GrapplingHook/rope_visual.gd` | Renderizar N segmentos desde wrap_points |
| `Player/Arms/GrapplingHook/grappling_hook_arm.gd` | Pasar surface_normal en señales |
| `Player/Arms/GrapplingHook/hook_projectile.gd` | Almacenar y exponer hit_normal, filtrar no_hook |
| `Player/player_3dEdited1.gd` | Pasar surface_normal a HookedState params |
| `project.godot` | Layer 8 = no_hook |

---

## 7. Parámetros de Referencia

```gdscript
# === CROSSHAIR ===
crosshair_detection_radius    = 20.0    # Rango de detección
crosshair_snap_angle          = 30.0    # Cono de snap para objetos chicos

# === SURFACE BEHAVIOR ===
ceiling_threshold             = -0.3    # normal.y < esto = techo (péndulo)
floor_threshold               = 0.3     # normal.y > esto = piso (pull)
wall_recoil_speed             = 25.0    # Velocidad de atracción a paredes
floor_pull_speed              = 40.0    # Velocidad de atracción a piso
floor_pull_gravity_mult       = 2.5     # Gravedad extra para fast pull

# === ROPE WRAPPING ===
wrap_offset                   = 0.05    # Offset del wrap point desde la superficie
unwrap_angle_threshold        = 5.0     # Grados de tolerancia para unwrap

# === NO-HOOK ===
no_hook_layer                 = 8       # Collision layer para superficies no-enganchables
no_hook_bitmask               = 128     # Bit 7
```
