extends Node
## Autoload: GameConstants
## Define todas las constantes globales, timings de coreografia estilo ajedrez,
## pesos heuristicos, transformacion local del tablero giratorio y enumeraciones.

const DEFAULT_GRID_SIZE: Vector2i = Vector2i(6, 6)
const MIN_GRID_SIZE: Vector2i = Vector2i(4, 4)
const MAX_GRID_SIZE: Vector2i = Vector2i(8, 8)
const CELL_SIZE: float = 2.0

# Timings base estilo Piezas de Ajedrez (Iteracion 2 - Seccion 1.1 y 1.2)
const THINK_DELAY: float = 0.55
const CHESS_MOVE_DURATION: float = 0.85
const SETTLE_DELAY: float = 0.35
const CHESS_ARC_HEIGHT: float = 1.15

const WEIGHT_SAFE: float = 1.0
const WEIGHT_SUSPICIOUS: float = 25.0

# Transformacion global del nodo giratorio del tablero (actualizada por SandboxBoard3D)
# donde el origen local (0, 0, 0) corresponde a la celda (0, 0).
var board_global_transform: Transform3D = Transform3D.IDENTITY
var current_speed_multiplier: float = 1.0

enum GodTool {
	TOGGLE_PIT,
	TOGGLE_WUMPUS,
	TOGGLE_WALL,
	MOVE_GOLD,
	CLEAR_CELL
}

enum FactState {
	UNKNOWN,
	SAFE,
	SUSPICIOUS,
	CONFIRMED
}

enum OverallState {
	UNKNOWN,
	SAFE,
	SUSPICIOUS,
	CONFIRMED_HAZARD
}

enum CellVisualState {
	UNKNOWN,
	SAFE,
	SUSPICIOUS,
	HAZARD_OR_WALL,
	VISITED_SAFE
}

enum SimState {
	PAUSED,
	RUNNING,
	STEPPING,
	WAITING_FOR_GOD_MODE,
	VICTORY,
	GAME_OVER
}

enum ControlRigMode {
	PC_FREECAM,
	STEAM_DECK_GYRO,
	VR_OPENXR
}

const ORTHOGONAL_DIRS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0)
]

func grid_to_world(cell: Vector2i, y_offset: float = 0.0) -> Vector3:
	return Vector3(float(cell.x) * CELL_SIZE, y_offset, float(cell.y) * CELL_SIZE)

func world_to_grid(world_pos: Vector3) -> Vector2i:
	var inv_xform: Transform3D = board_global_transform.affine_inverse()
	var local_pos: Vector3 = inv_xform * world_pos
	var gx: int = int(floor((local_pos.x + CELL_SIZE * 0.5) / CELL_SIZE))
	var gz: int = int(floor((local_pos.z + CELL_SIZE * 0.5) / CELL_SIZE))
	return Vector2i(gx, gz)

func world_ray_to_grid(ray_origin: Vector3, ray_normal: Vector3, grid_size: Vector2i) -> Vector2i:
	var inv_xform: Transform3D = board_global_transform.affine_inverse()
	var local_origin: Vector3 = inv_xform * ray_origin
	var local_normal: Vector3 = (inv_xform.basis * ray_normal).normalized()

	var local_plane: Plane = Plane(Vector3.UP, 0.0)
	var hit: Variant = local_plane.intersects_ray(local_origin, local_normal)
	if hit == null:
		return Vector2i(-1, -1)

	var local_pt: Vector3 = hit as Vector3
	var gx: int = int(floor((local_pt.x + CELL_SIZE * 0.5) / CELL_SIZE))
	var gz: int = int(floor((local_pt.z + CELL_SIZE * 0.5) / CELL_SIZE))
	if gx < 0 or gx >= grid_size.x or gz < 0 or gz >= grid_size.y:
		return Vector2i(-1, -1)
	return Vector2i(gx, gz)

func get_tool_display_name(tool_id: GodTool) -> String:
	match tool_id:
		GodTool.TOGGLE_PIT:
			return "Pozo (Pit)"
		GodTool.TOGGLE_WUMPUS:
			return "Wumpus"
		GodTool.TOGGLE_WALL:
			return "Muro (Wall)"
		GodTool.MOVE_GOLD:
			return "Mover Oro"
		GodTool.CLEAR_CELL:
			return "Limpiar Celda"
	return "Desconocido"

func get_sim_state_display_name(state: SimState) -> String:
	match state:
		SimState.PAUSED:
			return "PAUSADO"
		SimState.RUNNING:
			return "EJECUTANDO"
		SimState.STEPPING:
			return "PASO A PASO"
		SimState.WAITING_FOR_GOD_MODE:
			return "ESPERANDO MODO DIOS (BLOQUEADO)"
		SimState.VICTORY:
			return "VICTORIA (MISION CUMPLIDA)"
		SimState.GAME_OVER:
			return "GAME OVER (AGENTE ELIMINADO)"
	return "DESCONOCIDO"
