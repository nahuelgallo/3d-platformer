# Hook Crosshair, Flex Pole & Test Level Design

**Fecha:** 2026-03-31
**Estado:** Aprobado

---

## 1. Hook Crosshair (Mira de Enganche)

### Objetivo
Indicador visual que muestra al jugador exactamente dónde se enganchará el hook antes de dispararlo.

### Comportamiento
- **Detección:** Cada physics frame, busca objetos enganchables dentro de un radio esférico (`hook_max_distance = 20m`) centrado en el jugador
- **Selección por ángulo:** De todos los candidatos en rango, prioriza el que tiene menor ángulo respecto al centro de la cámara (forward vector). El jugador controla cuál elige moviendo la cámara
- **Capas detectables:** HookRing (layer 4), FlexPole (layer 7), JumpThruPlatform (layer 3, solo en aire)

### Estados visuales
- **Neutro (gris):** Nada enganchable en rango
- **Activo (color):** Apuntando a un punto válido — indicador 3D aparece en el punto de enganche (torus o esfera pequeña en world space)

### Arquitectura
- **Nodo:** `HookCrosshair` como hijo del Player
- **Script:** `hook_crosshair.gd`
- **Detección:** `Area3D` esférica (radio = `hook_max_distance`) para detectar candidatos + cálculo angular para seleccionar el mejor
- **Indicador 3D:** `MeshInstance3D` posicionado en world space sobre el punto de enganche seleccionado
- **UI 2D:** Crosshair en pantalla (centro) que cambia color según estado

### Integración con GrapplingHookArm
- `hook_crosshair.gd` expone `get_target() -> Node3D` y `get_attach_point() -> Vector3`
- `grappling_hook_arm.gd` consulta el crosshair al disparar en vez de usar raycast propio
- Si no hay target válido, el hook no dispara (o dispara al vacío según diseño actual)

---

## 2. Flex Pole (Palo Catapulta)

### Objetivo
Elemento de nivel tipo árbol/palo flexible. El jugador se engancha con el hook, dobla el palo hacia atrás con input, y al saltar el palo lo catapulta. Inspirado en Crimson Desert.

### Estructura de nodos
```
FlexPole (Node3D)
├── PoleBase (MeshInstance3D)        # Base fija (cilindro corto)
├── PoleBend (Node3D)                # Pivot de rotación para el doblez
│   └── PoleMesh (MeshInstance3D)    # Palo visual (cilindro largo)
├── HookPoint (Area3D)              # Punto de enganche — layer 7
│   └── CollisionShape3D            # Esfera de detección
└── flex_pole.gd
```

### Propiedades exportables
```gdscript
@export var max_bend_angle: float = 45.0      # Grados máximos de doblez
@export var bend_speed: float = 2.0           # Velocidad de doblez con input
@export var launch_force_min: float = 15.0    # Fuerza con doblez mínimo
@export var launch_force_max: float = 35.0    # Fuerza con doblez máximo
@export var spring_back_speed: float = 8.0    # Velocidad de retorno a posición original
@export var pole_height: float = 6.0          # Altura del palo
```

### Estados del Flex Pole
1. **IDLE:** Palo derecho, esperando enganche
2. **BENDING:** Jugador enganchado. `bend_amount` (0.0 → 1.0) controlado por input S. `PoleBend` rota visualmente
3. **RELEASE:** Jugador salta. Calcula fuerza y dirección, emite señal `pole_launched(force, direction)`
4. **SPRINGING_BACK:** Palo vuelve a posición original (lerp con `spring_back_speed`). Vuelve a IDLE

### Collision layer
- **Layer 7:** `flex_poles` — el crosshair los detecta como puntos enganchables

### Señales
```gdscript
signal pole_launched(launch_velocity: Vector3)
signal pole_grabbed(by: CharacterBody3D)
signal pole_released()
```

---

## 3. FlexPoleState (Estado del Jugador)

### Objetivo
Estado dedicado del jugador cuando está enganchado a un flex pole. Separado de HookedState porque la física es fundamentalmente distinta (no hay péndulo).

### Comportamiento
- **Entrada:** El hook se engancha a un FlexPole → `GrapplingHookArm` detecta que es flex pole → señal → transición a FlexPoleState
- **Posición:** El jugador se posiciona al lado del palo, agarrado
- **Input S (atrás):** Dobla el palo — aumenta `bend_amount` en el FlexPole (potencia)
- **Input W (adelante):** Reduce doblez — acerca al jugador al palo
- **Input A/D (costados):** Orbita al jugador alrededor del palo como pivot, cambiando la dirección de lanzamiento
- **Saltar (Space):** Lanza al jugador en dirección **opuesta** a su posición respecto al palo, con fuerza proporcional al `bend_amount`. Transiciona a Airborne
- **Sin gravedad de péndulo** — el jugador está "pegado" al palo, se mueve con él

### Dirección de lanzamiento
```
launch_direction = (pole_position - player_position).normalized()
launch_direction.y = max(launch_direction.y, 0.3)  # Siempre componente vertical
launch_velocity = launch_direction * lerp(launch_force_min, launch_force_max, bend_amount)
```

### Transiciones
- **Jump:** → Airborne (con velocidad de catapulta)
- **Soltar hook (click):** → Airborne (sin catapulta, velocidad neutra)
- **Tocar suelo:** No aplica (el jugador está suspendido del palo)

### Cámara
- FOV: 80 (default) — se podría subir a 85 durante el lanzamiento
- La cámara se aleja levemente para ver la curvatura del palo

---

## 4. Test Level — Arena Modular

### Objetivo
Nivel de prueba con zonas modulares para testear cada mecánica aislada + zona de combo. Las zonas cubren ~70% de la superficie del test level.

### Layout
```
              ┌─────────────────────┐
              │   ZONA 1 (Norte)    │
              │   Swing Básico      │
              │                     │
              └────────┬────────────┘
                       │
  ┌────────────────┐   │   ┌────────────────┐
  │  ZONA 3 (Oeste)│   │   │  ZONA 2 (Este) │
  │  Swing Encaden.├───┼───┤  Flex Poles     │
  │                │  HUB  │                 │
  └────────────────┘   │   └────────────────┘
                       │
              ┌────────┴────────────┐
              │   ZONA 4 (Sur)      │
              │   Combo / Flow      │
              │                     │
              └─────────────────────┘
```

### Hub Central
- Plataforma grande de spawn
- Checkpoint
- Pasillos/rampas que conectan a las 4 zonas
- Suelo sólido, seguro

### Zona 1 — Swing Básico (Norte)
- 3-4 hook rings en línea recta
- Distancias crecientes entre rings (5m, 8m, 12m)
- Plataformas de descanso entre cada ring
- Kill plane debajo
- Checkpoint al inicio
- **Testea:** Crosshair, apuntar, swing básico, soltar y aterrizar

### Zona 2 — Flex Poles (Este)
- 3-4 flex poles a distintas alturas
- Plataformas objetivo a distintas alturas y distancias (para aterrizar después del lanzamiento)
- Un pole bajo, uno medio, uno alto
- Espacio amplio para testear dirección orbital
- Checkpoint al inicio
- **Testea:** Enganche a pole, doblez, dirección de lanzamiento, potencia

### Zona 3 — Swing Encadenado (Oeste)
- 5-6 hook rings en zigzag
- Sin suelo entre rings (vacío)
- Distancias que requieren conservar momentum entre swings
- Plataforma solo al inicio y al final
- Checkpoint al inicio
- **Testea:** Soltar → re-enganchar en cadena, momentum, crosshair en movimiento

### Zona 4 — Combo / Flow (Sur)
- Recorrido mixto lineal
- Secuencia: plataforma → hook ring → flex pole → plataforma alta → slide → hook ring → meta
- Requiere usar todas las mecánicas en secuencia
- Checkpoint al inicio
- **Testea:** Transiciones entre mecánicas, flow general

### Elementos compartidos
- Kill plane global a y=-33
- Checkpoints al inicio de cada zona
- Construido con StaticBody3D + BoxShape3D (no CSG collision)
- Zonas grandes con espacio para iterar

---

## 5. Archivos Nuevos

```
Player/
├── hook_crosshair.gd                 # Mira de enganche
├── States/
│   └── flex_pole_state.gd            # Estado del jugador en flex pole

Level/Elements/
├── flex_pole.gd                      # Script del palo catapulta
└── flex_pole.tscn                    # Escena del palo (para instanciar en nivel)

Events.gd                             # Nuevas señales: pole_grabbed, pole_launched
```

### Modificaciones a archivos existentes
- `grappling_hook_arm.gd` — consultar crosshair para target, detectar FlexPole vs HookRing
- `Player/States/hooked_state.gd` — no cambia (flex pole usa estado separado)
- `project.godot` — layer 7 = flex_poles
- `test_level.tscn` — agregar las 4 zonas con todos los elementos

---

## 6. Parámetros de Referencia

```gdscript
# === CROSSHAIR ===
crosshair_detection_radius    = 20.0    # Mismo que hook_max_distance
crosshair_max_angle           = 30.0    # Grados máximos del cono de detección

# === FLEX POLE ===
max_bend_angle                = 45.0    # Grados
bend_speed                    = 2.0     # Por segundo
launch_force_min              = 15.0
launch_force_max              = 35.0
spring_back_speed             = 8.0
orbit_speed                   = 3.0     # Velocidad de orbita A/D
pole_height                   = 6.0     # Metros

# === FLEX POLE STATE ===
flex_pole_orbit_radius        = 2.0     # Distancia del jugador al palo
flex_pole_cam_fov             = 80.0    # FOV durante enganche
flex_pole_cam_distance        = 5.0     # Distancia de cámara
```
