# Mundo de Wumpus Autónomo 3D Sandbox (Godot 4.x)

Simulador 3D estilo maqueta (*tabletop*) del problema clásico del **Mundo de Wumpus** desarrollado en **Godot Engine 4.x (GDScript 2.0)** con arquitectura desacoplada por señales, **Motor de Inteligencia Artificial Híbrido (SE/RBR + `AStarGrid2D` + RBC 4R + XAI)**, edición en vivo en **Modo Dios**, coreografía de movimiento estilo **Piezas de Ajedrez** y soporte multiplataforma (**PC FreeCam**, **Steam Deck Gyro/Gamepad/Táctil** y **OpenXR VR**).

---

## Características Principales

### 1. Motor de IA Híbrido y Explicable (XAI)
- **Sistema Experto Basado en Reglas (`RuleEngineRBR.gd`)**: Bucle de inferencia *Forward Chaining* de punto fijo que evalúa las **8 Reglas de Producción (R1 a R8)**:
  - **R1 / R2**: Descarte deductivo de Pozos y Wumpus ante ausencia de brisa/hedor.
  - **R3**: Certificación de celdas 100% seguras (`peso A* = 1.0`).
  - **R4**: Propagación de sospecha y penalización heurística (`peso A* = 25.0`).
  - **R5**: Aislamiento deductivo de Pozo por eliminación (`solid = true`).
  - **R6**: Triangulación exacta del Wumpus y disparo automático de flecha en línea recta ortogonal.
  - **R7**: Captura del Lingote de Oro y cálculo de ruta segura de extracción hacia `(0, 0)`.
  - **R8**: Reconstrucción epistémica determinista en `< 0.2 ms` ante cualquier edición en vivo del Modo Dios.
- **Razonamiento Basado en Casos — Ciclo 4R (`CaseBasedReasoner4R.gd`)**:
  - Se activa cuando no existen celdas frontera `SAFE` alcanzables, ejecutando las fases **Retrieve, Reuse, Revise y Retain** sobre patrones locales de $3 \times 3$.
- **Estado de Bloqueo Seguro (`WAITING_FOR_GOD_MODE`)**:
  - Si todas las rutas posibles quedan encerradas por muros o peligros confirmados, el agente pausa el reloj sin consumir CPU y solicita intervención del Modo Dios en la consola XAI.

### 2. Coreografía Estilo Piezas de Ajedrez y Turntable 3D
- **Ciclo de Turno en 3 Tiempos (`SimulationManager.gd`)**:
  1. **Fase A (Deliberación — `0.55 s`)**: Lectura sensorial, inferencia R1–R8 / RBC y actualización visual XAI antes de mover la pieza.
  2. **Fase B (Movimiento Parabólico de Ajedrez — `0.85 s`)**: Giro deliberado (`0.18 s`), elevación e inclinación de $-12^\circ$, arco parabólico $Y(t) = 4 \cdot 1.15 \cdot t \cdot (1 - t)$ y aterrizaje con micro-compresión (`TRANS_BOUNCE`).
  3. **Fase C (Asentamiento — `0.35 s`)**: Pausa tras posar la pieza antes del siguiente turno.
- **Velocidad Ajustable en Vivo**: Selector en el HUD entre `0.5x Lento`, `1.0x Ajedrez` y `2.0x Rápido`.
- **Rotación del Tablero con Teclas Configurables (`SandboxBoard3D.gd`)**:
  - Giro continuo con inercia (`Flechas Izquierda / Derecha`), pasos exactos de $90^\circ$ (`Shift + Flecha`), inclinación de $0^\circ$ a $25^\circ$ (`Flechas Arriba / Abajo`) y proyección inversa local (`GameConstants.world_ray_to_grid`) para mantener precisión milimétrica del ratón/táctil/láser VR en cualquier ángulo.

### 3. Tres Modos de Cámara y Control
- **PC (`RigPC_FreeCam.gd` — `F1`)**: Vuelo libre 3D con `Click Derecho + WASD/E/Q/Shift` y edición Modo Dios con `Click Izquierdo`.
- **Steam Deck (`RigDeck_Gyro.gd` — `F2`)**: Cámara orbital con giroscopio nativo (`Input.get_gyroscope()`), puntero de precisión con `L2`, D-Pad/Sticks y pantalla táctil.
- **Realidad Virtual OpenXR (`RigVR_Quest.gd` — `F3` / Auto)**: `XROrigin3D` con láser 3D en mano derecha y panel holográfico XAI (`VR_WristPanel3D.gd`) en la muñeca izquierda.

---

## Estructura del Proyecto

```text
res://
├── autoloads/
│   ├── GameConstants.gd
│   ├── EventBus.gd
│   └── PlatformManager.gd
├── core_data/
│   ├── WorldTruthData.gd
│   ├── CellBeliefData.gd
│   └── EpistemicMapData.gd
├── ai_engine/
│   ├── NavigationPlannerAStar.gd
│   ├── RuleEngineRBR.gd
│   ├── CaseBasedReasoner4R.gd
│   └── KnowledgeEngine.gd
├── simulation/
│   └── SimulationManager.gd
├── world_3d/
│   ├── MainSandbox.tscn
│   ├── MainSandbox.gd
│   ├── SandboxBoard3D.gd
│   ├── Tile3D.gd
│   ├── PathVisualizer3D.gd
│   └── AgentVisual3D.gd
├── player_rigs/
│   ├── RigSwitcher.gd
│   ├── RigPC_FreeCam.gd
│   ├── RigDeck_Gyro.gd
│   └── RigVR_Quest.gd
└── ui_xai/
    ├── HUD_Controller.gd
    └── VR_WristPanel3D.gd
```

---

## Ejecución en Godot 4
1. Clona este repositorio y abre **Godot Engine 4.3+**.
2. Importa el archivo `project.godot`.
3. Presiona **`F5`** para ejecutar la escena principal `res://world_3d/MainSandbox.tscn`.
