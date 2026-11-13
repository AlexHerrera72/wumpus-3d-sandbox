class_name EpistemicMapData
extends RefCounted
## Capa de Datos Puros: EpistemicMapData
## Base de Hechos completa del Agente Explorador. Almacena las creencias de cada
## celda, el historial de celdas visitadas y el estado de inventario/mision.

var grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var cells: Dictionary = {} # Vector2i -> CellBeliefData
var visited_cells: Array[Vector2i] = []

var agent_pos: Vector2i = Vector2i.ZERO
var agent_facing: Vector2i = Vector2i(1, 0)
var has_arrow: bool = true
var has_gold: bool = false
var wumpus_killed: bool = false

func _init(initial_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE) -> void:
	initialize_grid(initial_size)

func initialize_grid(new_size: Vector2i) -> void:
	grid_size = new_size
	cells.clear()
	visited_cells.clear()
	agent_pos = Vector2i.ZERO
	agent_facing = Vector2i(1, 0)
	has_arrow = true
	has_gold = false
	wumpus_killed = false

	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var pos: Vector2i = Vector2i(x, y)
			var belief: CellBeliefData = CellBeliefData.new(pos)
			if pos == Vector2i.ZERO:
				belief.pit_state = GameConstants.FactState.SAFE
				belief.wumpus_state = GameConstants.FactState.SAFE
				belief.overall_state = GameConstants.OverallState.SAFE
			cells[pos] = belief

func is_within_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y

func get_cell(cell: Vector2i) -> CellBeliefData:
	return cells.get(cell, null) as CellBeliefData

func get_orthogonal_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir: Vector2i in GameConstants.ORTHOGONAL_DIRS:
		var n: Vector2i = cell + dir
		if is_within_bounds(n):
			result.append(n)
	return result

func get_passable_orthogonal_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for n: Vector2i in get_orthogonal_neighbors(cell):
		var belief: CellBeliefData = get_cell(n)
		if belief != null and not belief.is_wall:
			result.append(n)
	return result

func register_visited_percepts(cell: Vector2i, percepts: Dictionary) -> void:
	var belief: CellBeliefData = get_cell(cell)
	if belief == null:
		return

	belief.is_wall = bool(percepts.get("is_wall", false))
	if belief.is_wall:
		belief.overall_state = GameConstants.OverallState.CONFIRMED_HAZARD
		return

	belief.visited = true
	belief.breeze = bool(percepts.get("breeze", false))
	belief.stench = false if wumpus_killed else bool(percepts.get("stench", false))
	belief.glitter = bool(percepts.get("glitter", false))
	belief.pit_state = GameConstants.FactState.SAFE
	belief.wumpus_state = GameConstants.FactState.SAFE
	belief.overall_state = GameConstants.OverallState.SAFE

	if not visited_cells.has(cell):
		visited_cells.append(cell)

func mark_wall_state(cell: Vector2i, wall_active: bool) -> void:
	var belief: CellBeliefData = get_cell(cell)
	if belief == null:
		return
	belief.is_wall = wall_active
	if wall_active:
		belief.visited = false
		visited_cells.erase(cell)
		belief.overall_state = GameConstants.OverallState.CONFIRMED_HAZARD

func reset_non_visited_deductions() -> void:
	for pos: Vector2i in cells.keys():
		var belief: CellBeliefData = cells[pos] as CellBeliefData
		belief.reset_deductions_for_reconstruction(wumpus_killed)

func build_visual_states_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for pos: Vector2i in cells.keys():
		var belief: CellBeliefData = cells[pos] as CellBeliefData
		snapshot[pos] = belief.to_visual_state()
	return snapshot
