# Proyecto Scioli - Engine Base de Plataformero 3D

## Vision

Plataformero 3D con movimiento estilo Mario Odyssey en suelo (versatil, muchas opciones por input) y control aereo estilo Spider-Man (momentum, flow, mantener velocidad). El jugador es un robot con un brazo derecho intercambiable (base: punos, especial: grappling hook). La meta es construir un engine base de plataformero 3D solido y luego sumar mecanicas unicas.

**Motor:** Godot 4.5 (Forward Plus)
**Referencia GDD:** Proyecto Scioli (originalmente 2D, adaptado a 3D)

---

## Arquitectura del Proyecto

### Estructura de carpetas objetivo

```
3d-platformer/
├── CLAUDE.md
├── Events.gd                          # Autoload - Senales globales
├── project.godot
│
├── Core/                               # Sistemas centrales reutilizables
│   ├── StateMachine/
│   │   ├── state_machine.gd           # StateMachine generica (reutilizable)
│   │   └── state.gd                   # Clase base State
│   └── CameraSystem/
│       ├── camera_rig.gd              # Rig principal de camara
│       └── camera_states/             # Estados de camara (explore, combat, swing, etc.)
│
├── Player/
│   ├── player.tscn                    # Escena del jugador (CharacterBody3D)
│   ├── player.gd                      # Controller principal (delega a StateMachine)
│   ├── States/                        # Estados del jugador (movimiento)
│   │   ├── idle_state.gd
│   │   ├── walk_state.gd
│   │   ├── run_state.gd
│   │   ├── airborne_state.gd
│   │   ├── slide_state.gd
│   │   ├── crouch_state.gd
│   │   └── hooked_state.gd           # Cuando esta enganchado al gancho
│   ├── Arms/                          # Sistema de brazos
│   │   ├── arm_socket.gd             # Socket que sostiene el brazo activo
│   │   ├── arm_base.gd               # Clase base para todos los brazos
│   │   ├── FistArm/                   # Brazo base (punos)
│   │   │   └── fist_arm.gd
│   │   └── GrapplingHook/            # Brazo gancho
│   │       ├── grappling_hook_arm.gd
│   │       └── hook_projectile.gd
│   ├── Skin/                          # Visual del personaje
│   │   ├── robot_skin.gd
│   │   └── robot_skin.tscn
│   └── Robot/
│       └── RobotBase.glb
│
├── Level/
│   ├── test.tscn                      # Escena de prueba
│   ├── level.tscn                     # Nivel actual
│   └── Elements/                      # Elementos reutilizables del nivel
│       ├── kill_plane.gd
│       ├── flag_3d.gd
│       ├── jump_thru_platform.gd
│       └── hook_ring.gd
│
└── UI/
    ├── debug_hud.tscn                 # HUD de debug (velocidad, estado, fps)
    └── flag_reached_screen.tscn
```

### Arquitectura: State Machine del Jugador

El jugador usa una **StateMachine generica** que se puede reutilizar para otros sistemas (brazos, enemigos, etc).

```
Player (CharacterBody3D)
  ├── PlayerStateMachine (StateMachine)
  │   ├── IdleState
  │   ├── WalkState
  │   ├── RunState
  │   ├── AirborneState          # Salta, cae, control aereo
  │   ├── SlideState             # Deslizamiento con momentum
  │   ├── CrouchState            # Agachado estatico
  │   └── HookedState            # Enganchado al grappling hook
  ├── ArmSocket (Node3D)         # Brazo derecho intercambiable
  │   └── [ArmActivo]            # FistArm o GrapplingHookArm
  ├── RobotSkin                  # Visual + animaciones
  ├── CollisionShape3D           # Capsula normal
  ├── CrouchCollisionShape3D     # Capsula reducida (para crouch/slide)
  └── CameraRig                  # Sistema de camara con estados
```

**Como funciona:**
- `player.gd` no tiene logica de movimiento. Solo conecta input y delega al estado activo.
- Cada `State` define: `enter()`, `exit()`, `process_physics(delta)`, `process_input(event)`.
- Los estados cambian entre si via `state_machine.transition_to("NombreEstado")`.
- La velocidad (`velocity`) vive en el Player y los estados la modifican.

### Arquitectura: Sistema de Brazos

```
ArmSocket (Node3D)                      # Posicion en el brazo derecho del robot
  └── arm_socket.gd
        var current_arm: ArmBase        # Brazo actualmente equipado
        func equip(arm: ArmBase)        # Cambiar brazo
        func unequip()                  # Sacar brazo

ArmBase (Node3D)                        # Clase base - interfaz comun
  └── arm_base.gd
        func primary_action()           # Click izquierdo
        func secondary_action()         # Click derecho
        func release_action()           # Soltar input
        func get_player_state() -> String   # Que estado forzar en el player (ej: "Hooked")
        signal arm_state_changed(state) # Para que el player reaccione

FistArm extends ArmBase                 # Brazo por defecto
  └── fist_arm.gd
        primary_action() -> golpe/interaccion
        secondary_action() -> nada por ahora

GrapplingHookArm extends ArmBase       # Brazo gancho
  └── grappling_hook_arm.gd
        Estados internos: IDLE, CHARGING, FLYING, ATTACHED
        primary_action() -> carga/dispara/suelta gancho
        secondary_action() -> recoil (acorta cuerda)
        Cuando ATTACHED -> pide al player cambiar a HookedState
```

**Porque esta arquitectura:**
- Cada brazo es independiente. Agregar un brazo nuevo = crear un script que extienda `ArmBase`.
- El Player no sabe que brazo tiene equipado. Solo llama `primary_action()` / `secondary_action()`.
- El brazo puede pedir al player cambiar de estado via senal (ej: gancho enganchado -> HookedState).
- A futuro, se puede agregar un segundo socket (brazo izquierdo) sin cambiar nada del sistema.

### Arquitectura: Sistema de Camara

```
CameraRig (Node3D)
  ├── camera_rig.gd
  │     var current_state: CameraState
  │     func transition_to(state_name)
  │     # Interpola suavemente entre estados
  ├── SpringArm3D
  │   └── Camera3D
  └── CameraStates/
        ├── ExploreState       # Default: camara libre con mouse (actual)
        │   fov: 80, distance: normal, follow_speed: normal
        ├── SprintState        # Corriendo rapido
        │   fov: 90, distance: normal, follow_speed: rapido
        ├── SwingState         # Balanceandose en gancho
        │   fov: 85, distance: alejada, follow_speed: lento (cinematico)
        ├── PuzzleState        # Camara fija para puzzles
        │   posicion fija, sin input de mouse
        └── CutsceneState     # Cinematicas
            posicion/rotacion definida por el nivel
```

**Transiciones:**
- El Player notifica a la CameraRig cuando cambia de estado.
- La CameraRig interpola FOV, distancia y posicion suavemente (lerp/tween).
- Ejemplo: correr -> FOV sube de 80 a 90 gradualmente. Dejar de correr -> baja suave.

---

## Plan de Desarrollo por Fases

Cada fase es testeable de forma independiente. Se prueba, se ajusta, y recien se avanza.

### FASE 0: Limpieza y Base Solida
**Objetivo:** Proyecto limpio, funcional, sin archivos muertos.

- [x] **0.1** Eliminar player_3d.gd (deprecado, reemplazado por player_3dEdited1.gd)
- [ ] **0.2** Mover interactables (flag_3d, kill_plane, flag_reached_screen) a Level/Elements/ *(hacer desde Godot editor para que actualice UIDs)*
- [ ] **0.3** Decidir sobre sophia_skin (eliminar o archivar) *(hacer desde Godot editor)*
- [x] **0.4** Implementar respawn en KillPlane (guarda spawn position, resetea al morir)
- [ ] **0.5** Verificar fix de animacion de run (duplicate en _setup_animations) *(probar en Godot)*
- [x] **0.6** Ajustar coyote_duration de 1.0s a 0.15s
- [x] **0.7** Crear Debug HUD basico (F3 para toggle, muestra velocidad/estado/fps/posicion)
- [x] **0.8** Agregar comentarios explicativos a player_3dEdited1.gd y robot_skin.gd

**Test:** Moverse, saltar, morir, respawnear. Todas las animaciones funcionan. F3 muestra debug HUD.

---

### FASE 1: State Machine + Movimiento con Momentum
**Objetivo:** Reemplazar el controller monolitico por una state machine con momentum real.

- [ ] **1.1** Crear Core/StateMachine/state_machine.gd y state.gd (genericos, reutilizables)
- [ ] **1.2** Crear Player/States/ con estados basicos:
  - IdleState: sin movimiento, friccion alta, transiciona a Walk/Run/Airborne/Crouch
  - WalkState: movimiento base, aceleracion progresiva
  - RunState: sprint (Shift), velocidad mayor, FOV mas amplio
  - AirborneState: control aereo limitado, momentum del salto se conserva, gravedad diferenciada (subida vs caida)
- [ ] **1.3** Migrar logica de player_3dEdited1.gd a los estados
  - Mover coyote time y jump buffer a AirborneState / transiciones
  - Mover squash & stretch a las transiciones entre estados
- [ ] **1.4** Sistema de friccion por estado
  - Cada estado define su propia friccion y aceleracion
  - El momentum se conserva entre transiciones de estado
- [ ] **1.5** Control aereo estilo Spider-Man
  - En el aire: puedo redirigir pero no frenar
  - El techo de velocidad aereo = velocidad al momento de saltar/caer
  - Si entro al aire con mucha velocidad (slide jump, catapulta), la conservo
- [ ] **1.6** Actualizar Debug HUD para mostrar estado activo

**Test:** El movimiento se siente diferente en cada estado. El aire conserva momentum. Frenar toma tiempo.

---

### FASE 2: Crouch y Slide
**Objetivo:** Slide con conservacion de momentum. Base para slide jump.

- [ ] **2.1** CrouchState: collider reducido, deteccion de techo (ShapeCast3D arriba)
  - No puede pararse si hay techo
  - Velocidad reducida, control total
- [ ] **2.2** SlideState: crouch + velocidad minima + suelo
  - Boost inicial de velocidad al entrar
  - Friccion baja (se desliza largo)
  - No hay aceleracion manual (el jugador no controla la direccion, solo gira suavemente)
  - Se cancela si velocidad baja de umbral minimo -> vuelve a CrouchState
- [ ] **2.3** Slide al aterrizar con crouch
  - Si aterriza con crouch mantenido y velocidad > umbral -> entra a SlideState directo
  - Conserva momentum aereo completo
- [ ] **2.4** Transferencia de momentum en rampas (superficies diagonales)
  - Parte del momentum vertical se transfiere a horizontal
- [ ] **2.5** Animaciones: usar CrouchBegin -> Crouch_Idle_Loop (ya hecho), agregar slide visual

**Test:** Slide se siente rapido y satisfactorio. Aterrizar en slide conserva velocidad. Las rampas aceleran.

---

### FASE 3: Slide Jump
**Objetivo:** Mecanica clave de velocidad avanzada para speedrunning.

- [x] **3.1** Condiciones: suelo + SlideState + crouch + salto
- [x] **3.2** Efectos: +35% velocidad horizontal, +8-10% altura vs salto normal
- [x] **3.3** Fase explosiva (~200ms): sin friccion, velocidad se conserva intacta
- [x] **3.4** Fase de decaimiento: velocidad extra se interpola hacia velocidad normal
- [x] **3.5** Combo: slide -> slide jump -> aterrizar con crouch -> slide -> slide jump (loop de velocidad)

**Test:** Se puede encadenar slide -> slide jump para ganar velocidad progresivamente. Se siente poderoso.

---

### FASE 4: Sistema de Camara Dinamica
**Objetivo:** Camara que responde al estado del jugador.

- [x] **4.1** Crear CameraRig con estado base (ExploreState = actual)
- [x] **4.2** SprintState: FOV sube a ~90 al correr, baja suave al frenar
- [x] **4.3** Transiciones suaves entre estados (lerp de FOV, distancia, offset)
- [ ] **4.4** Preparar estructura para SwingState, PuzzleState, CutsceneState (vacios por ahora)

**Test:** Correr se siente mas rapido gracias al FOV. Las transiciones son suaves, no abruptas.

---

### FASE 5: Sistema de Brazos - Base
**Objetivo:** Infraestructura de brazos intercambiables + brazo de punos.

- [ ] **5.1** Crear arm_base.gd (clase base con interfaz: primary/secondary/release)
- [ ] **5.2** Crear arm_socket.gd (equip/unequip, delega inputs al brazo activo)
- [ ] **5.3** Crear FistArm (brazo base: golpe simple con primary_action)
  - Animacion de golpe del robot
  - Puede interactuar con objetos del nivel (botones, palancas)
- [ ] **5.4** Integrar ArmSocket en Player: left_click -> current_arm.primary_action()
- [ ] **5.5** Input para cambiar brazo (tecla Q o rueda del mouse)

**Test:** El jugador puede golpear con el puno. Cambiar de brazo funciona (aunque solo hay uno).

---

### FASE 6: Elementos de Nivel
**Objetivo:** Vocabulario del nivel para testear mecanicas.

- [ ] **6.1** Plataformas jump-thru (colision solo desde arriba, drop con crouch + abajo)
- [ ] **6.2** Aros de gancho (RING) - solo visual por ahora, preparar collision layer
- [ ] **6.3** Rampas con transferencia de momentum
- [ ] **6.4** Checkpoints (posicion de respawn)
- [ ] **6.5** Nivel de prueba que combine todo

**Test:** Se puede navegar un nivel usando walk, run, slide, slide jump, jump-thru y rampas.

---

### FASE 7: Grappling Hook - Base
**Objetivo:** El gancho en su forma mas basica, como brazo intercambiable.

- [ ] **7.1** GrapplingHookArm extends ArmBase
- [ ] **7.2** IDLE -> CHARGING (mantener click): indicador visual de carga
- [ ] **7.3** CHARGING -> FLYING: proyectil viaja hacia donde apunta la camara
  - RayCast3D o Area3D para deteccion
  - Solo engancha: RING y jump-thru (en aire)
- [ ] **7.4** FLYING -> ATTACHED: gancho conectado
  - Visual de cuerda (ImmediateMesh o Line con nodos)
  - Player pasa a HookedState via senal
- [ ] **7.5** HookedState en Player: restriccion de movimiento por largo de cuerda
- [ ] **7.6** Soltar gancho: vuelve a AirborneState con velocidad actual

**Test:** Disparar, engancharse, colgar, soltar. El jugador queda suspendido y puede soltarse.

---

### FASE 8: Grappling Hook - Swing y Momentum
**Objetivo:** Oscilacion y fisica de cuerda.

- [ ] **8.1** Swing: inputs laterales impulsan oscilacion
- [ ] **8.2** Subir/bajar cuerda (W/S)
- [ ] **8.3** Elasticidad: stretch temporal segun velocidad de impacto
- [ ] **8.4** Conservacion de momentum durante swing
- [ ] **8.5** CameraRig: SwingState (alejarse, FOV mas amplio para ver puntos de enganche)

**Test:** Balancearse se siente natural. La cuerda tiene elasticidad. La camara ayuda a ver los aros.

---

### FASE 9: Grappling Hook - Recoil y Catapulta
**Objetivo:** Mecanica avanzada: recoil + eyeccion.

- [ ] **9.1** Recoil (click derecho): acorta cuerda, congela angulo
- [ ] **9.2** Eyeccion: al llegar al punto de anclaje, lanzar al jugador
  - Fuerza = largo inicial + stretch acumulado
  - Direccion = angulo congelado
- [ ] **9.3** Combos: swing -> recoil -> eyeccion para catapultas
- [ ] **9.4** Conversion de caidas verticales en impulso horizontal via gancho

**Test:** Se pueden encadenar ganchos para traversar grandes distancias sin tocar el suelo.

---

### FASE 10: Nivel de Prueba Completo + Pulido
**Objetivo:** Un nivel que testee todo junto. Pulido visual y de sensacion.

- [ ] **10.1** Nivel con todas las mecanicas (slide, hook, jump-thru, rampas, aros)
- [ ] **10.2** Tutorial implicito (cada seccion ensena una mecanica)
- [ ] **10.3** Timer de speedrun
- [ ] **10.4** Particulas: slide (chispas), gancho (impacto), aterrizaje (polvo)
- [ ] **10.5** Screen shake en impactos
- [ ] **10.6** Trail visual en velocidades altas
- [ ] **10.7** Sonido basico (slide, gancho, swing, aterrizaje)

---

## Mecanicas del GDD vs Plan

| Mecanica (GDD) | Fase | Estado |
|----------------|------|--------|
| Movimiento base (aceleracion, friccion) | 1 | PARCIAL |
| Coyote time | 0 | HECHO (ajustar valor) |
| Jump buffer | 0 | HECHO |
| Jump cut | 0 | HECHO |
| Crouch (reducir collider) | 2 | PARCIAL (falta collider) |
| Slide (boost + friccion) | 2 | NO HECHO |
| Slide al aterrizar | 2 | NO HECHO |
| Slide Jump | 3 | NO HECHO |
| Transferencia momentum diagonales | 2 | NO HECHO |
| Control aereo limitado | 1 | PARCIAL |
| Grappling Hook base | 7 | HECHO (disparo, enganche, pendulo, wall recoil, floor pull) |
| Swing / oscilacion | 8 | HECHO (pendulo con rope wrapping, subir/bajar cuerda) |
| Elasticidad cuerda | 8 | NO HECHO |
| Recoil + catapulta | 9 | PARCIAL (recoil con left click en pendulo, falta catapulta) |
| Bullet time (aim) | - | HECHO (aim_state + airborne post-hook, 1.5s, 25% speed) |
| Plataformas jump-thru | 6 | NO HECHO |
| Aros de gancho (RING) | 6 | HECHO (HookRing con snap angular en crosshair) |
| FlexPole | - | HECHO (poste flexible con enganche y lanzamiento) |
| Hook Crosshair | - | HECHO (mira con snap angular, indicador 3D torus) |

---

## Parametros de Referencia

```gdscript
# === MOVIMIENTO BASE ===
move_speed           = 8.0
sprint_speed         = 14.0
crouch_speed         = 4.0
acceleration         = 20.0
air_acceleration     = 5.0        # POR IMPLEMENTAR
friction_normal      = 15.0       # POR IMPLEMENTAR
friction_slide       = 2.0        # POR IMPLEMENTAR
friction_air         = 0.5        # POR IMPLEMENTAR

# === SALTO ===
jump_impulse         = 12.0
coyote_duration      = 0.15       # AJUSTAR (actual: 1.0)
jump_buffer_duration = 0.25
fall_gravity_mult    = 1.8
jump_cut_mult        = 0.4
gravity              = -30.0

# === SLIDE ===
slide_boost          = 1.35       # POR IMPLEMENTAR
slide_min_speed      = 3.0        # POR IMPLEMENTAR

# === SLIDE JUMP ===
slide_jump_h_boost   = 1.35       # POR IMPLEMENTAR (+35%)
slide_jump_v_boost   = 1.10       # POR IMPLEMENTAR (+8-10%)
explosive_phase_ms   = 200        # POR IMPLEMENTAR

# === GRAPPLING HOOK ===
hook_charge_max      = 1.5        # IMPLEMENTADO (CHARGE_TIME en grappling_hook_arm.gd)
hook_speed           = 80.0       # IMPLEMENTADO (era 40, subido a 80)
hook_max_distance    = 20.0       # IMPLEMENTADO
rope_elasticity      = 0.15       # POR IMPLEMENTAR
recoil_speed         = 25.0       # IMPLEMENTADO (RECOIL_SPEED en hooked_state.gd)

# === BULLET TIME ===
bullet_time_scale    = 0.25       # IMPLEMENTADO (25% velocidad, en aim_state y airborne_state)
bullet_time_duration = 1.5        # IMPLEMENTADO (1.5s reales max)

# === CAMARA ===
fov_default          = 80
fov_sprint           = 90
fov_swing            = 85
camera_lerp_speed    = 5.0
```

---

## Convenciones

- **Idioma del codigo:** ingles (variables, funciones, clases)
- **Idioma de comentarios:** espanol
- **Estructura:** por feature (Player/, Level/, Core/)
- **Scripts:** snake_case.gd
- **Escenas:** snake_case.tscn
- **Clases:** PascalCase (class_name)
- **Senales globales:** via autoload Events.gd
- **State machines:** genericas en Core/, especializadas donde se usan
- **Brazos:** extienden ArmBase, registrados en ArmSocket
- **Inputs:** definidos en project.godot, referenciados por nombre de accion

---

## Notas Tecnicas

- Animaciones de GLB son read-only. Siempre duplicar antes de modificar loop_mode.
- AnimationPlayer.speed_scale funciona. AnimationTree.speed_scale NO existe en Godot 4.5.
- Paths en Godot son case-sensitive: siempre `res://Player/` (P mayuscula).
- CharacterBody3D.move_and_slide() actualiza is_on_floor() internamente.
- Para jump-thru platforms en 3D: collision layers/masks + AnimatableBody3D con one-way collision.
- StateMachine generica permite reutilizarla para: player, brazos, camara, enemigos.

---

## Estado Actual

**Fase activa:** Bionic Commando Hook System (branch: feature/bionic-commando-hook)
**Ultima tarea:** Ajustes de game feel al grappling hook
- HOOK_SPEED subido de 40 a 80 (proyectil viaja al doble de velocidad)
- Bullet time (camara lenta) agregado a AimState (right click en suelo activa slow-mo, 1.5s max, 25% velocidad)
- Bullet time ya existia en AirborneState post-hook; ahora tambien funciona al apuntar desde el suelo

**Pendiente / Bugs conocidos:**
- Transicion brusca al engancharse en pendulo (player se teletransporta a posicion acortada de cuerda)
- Player choca con el piso al engancharse a techos/paredes altas (AUTO_RETRACT_RATIO 75% no alcanza)
- Left click en pendulo impulsa al player (recoil) en vez de re-lanzar hook
- Micro-escalones en el suelo bloquean al player (floor_snap_length=0.05 muy bajo)
- Falta barra de UI mostrando tiempo restante de bullet time

**Pendiente en Godot editor (de sesiones anteriores):**
- Agregar nodo `LedgeGrab` (tipo Node) bajo `PlayerStateMachine` en la escena del player
- Asignar script `res://Player/States/ledge_grab_state.gd`
- Sin ese nodo, la state machine no encuentra el estado y el ledge grab no funciona
**Siguiente paso:** Resolver los 5 bugs/ajustes pendientes del hook system.

**Notas de nivel:**
- NO usar `Use Collision` de CSG para suelos/plataformas (trimesh genera micro-paredes en bordes)
- Usar `StaticBody3D` + `CollisionShape3D` (BoxShape3D) para collision de suelo
- Para slopes: BoxShape3D rotados
- Al duplicar CollisionShape3D: hacer **Make Unique** en el recurso Shape para que no compartan tamaño
- No escalar StaticBody3D con escala no uniforme: cambiar el Size del BoxShape3D/BoxMesh directamente
