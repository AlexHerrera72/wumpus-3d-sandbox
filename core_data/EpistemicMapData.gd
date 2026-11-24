class_name EpistemicMapData
extends RefCounted
## Capa de Datos Puros: EpistemicMapData
## Base de Hechos multipiso (hasta 5 pisos) del Agente Explorador.
## Soporta multiples flechas (arrow_count), multiples Wumpus, portales Azul/Naranja
## y escaleras entre pisos.

var grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var floor_count: int = 1
var cells: Dictionary = {} # Vector3i -> CellBeliefData
var visited_cells: Array[Vector3i] = []
var known_special_links: Array[Array] = [] # Array de [Vector3i_a, Vector3i_b] (portales y escaleras)

var agent_pos: Vector3i = Vector3i.ZERO
var agent_facing: Vector2i = Vector2i(1, 0)
var arrow_count: int = 1
var has_gold: bool = false

func _init(initial_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE, initial_floors: int = 1) -> void:
	initialize_grid(initial_size, initial_floors)

func initialize_grid(new_size: Vector2i, new_floor_count: int = 1) -> void:
	grid_size = new_size
	floor_count = clampi(new_floor_count, 1, GameConstants.MAX_FLOORS)
	cells.clear()
	visited_cells.clear()
	known_special_links.clear()
	agent_pos = Vector3i(0, 0, 0)
	agent_facing = Vector2i(1, 0)
	arrow_count = 1
	has_gold = false

	for fl: int in range(floor_count):
		for y: int in range(grid_size.y):
			for x: int in range(grid_size.x):
				var pos: Vector3i = Vector3i(x, y, fl)
				var belief: CellBeliefData = CellBeliefData.new(pos)
				if pos == Vector3i(0, 0, 0):
					belief.pit_state = GameConstants.FactState.SAFE
					belief.wumpus_state = GameConstants.FactState.SAFE
					belief.overall_state = GameConstants.OverallState.SAFE
				cells[pos] = belief

func is_within_bounds(cell: Vector3i) -> bool:
	return (
		cell.x >= 0 and cell.x < grid_size.x
		and cell.y >= 0 and cell.y < grid_size.y
		and cell.z >= 0 and cell.z < floor_count
	)

func get_cell(cell: Vector3i) -> CellBeliefData:
	return cells.get(cell, null) as CellBeliefData

func get_orthogonal_neighbors(cell: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for dir: Vector2i in GameConstants.ORTHOGONAL_DIRS:
		var n: Vector3i = Vector3i(cell.x + dir.x, cell.y + dir.y, cell.z)
		if is_within_bounds(n):
			result.append(n)
	return result

func get_passable_orthogonal_neighbors(cell: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for n: Vector3i in get_orthogonal_neighbors(cell):
		var belief: CellBeliefData = get_cell(n)
		if belief != null and not belief.is_wall:
			result.append(n)
	return result

func register_special_link(a: Vector3i, b: Vector3i) -> void:
	if not is_within_bounds(a) or not is_within_bounds(b) or a == b:
		return
	var ca: CellBeliefData = get_cell(a)
	var cb: CellBeliefData = get_cell(b)
	if ca != null and not ca.special_targets.has(b):
		ca.special_targets.append(b)
	if cb != null and not cb.special_targets.has(a):
		cb.special_targets.append(a)

	for link: Array in known_special_links:
		if (link[0] == a and link[1] == b) or (link[0] == b and link[1] == a):
			return
	known_special_links.append([a, b])

func clear_special_links() -> void:
	known_special_links.clear()
	for pos: Vector3i in cells.keys():
		var belief: CellBeliefData = cells[pos] as CellBeliefData
		belief.special_targets.clear()

func register_visited_percepts(cell: Vector3i, percepts: Dictionary) -> void:
	var belief: CellBeliefData = get_cell(cell)
	if belief == null:
		return

	belief.is_wall = bool(percepts.get("is_wall", false))
	if belief.is_wall:
		belief.overall_state = GameConstants.OverallState.CONFIRMED_HAZARD
		return

	belief.visited = true
	belief.breeze = bool(percepts.get("breeze", false))
	belief.stench = bool(percepts.get("stench", false))
	belief.glitter = bool(percepts.get("glitter", false))
	belief.pit_state = GameConstants.FactState.SAFE
	belief.wumpus_state = GameConstants.FactState.SAFE
	belief.overall_state = GameConstants.OverallState.SAFE

	var adj_walls: Array = percepts.get("adjacent_walls", [])
	for w_var: Variant in adj_walls:
		var w_pos: Vector3i = w_var as Vector3i
		if is_within_bounds(w_pos):
			mark_wall_state(w_pos, true)

	var spec_dests: Array = percepts.get("special_destinations", [])
	for d_var: Variant in spec_dests:
		var dest: Vector3i = d_var as Vector3i
		if dest.x >= 0:
			register_special_link(cell, dest)

	if not visited_cells.has(cell):
		visited_cells.append(cell)

func mark_wall_state(cell: Vector3i, wall_active: bool) -> void:
	var belief: CellBeliefData = get_cell(cell)
	if belief == null:
		return
	belief.is_wall = wall_active
	if wall_active:
		belief.visited = false
		visited_cells.erase(cell)
		belief.overall_state = GameConstants.OverallState.CONFIRMED_HAZARD

func reset_non_visited_deductions() -> void:
	for pos: Vector3i in cells.keys():
		var belief: CellBeliefData = cells[pos] as CellBeliefData
		belief.reset_deductions_for_reconstruction()

func build_visual_states_snapshot_3d() -> Dictionary:
	var snapshot: Dictionary = {}
	for pos: Vector3i in cells.keys():
		var belief: CellBeliefData = cells[pos] as CellBeliefData
		snapshot[pos] = belief.to_visual_state()
	return snapshot

func build_visual_states_snapshot_floor(floor_idx: int) -> Dictionary:
	var snapshot: Dictionary = {}
	for pos: Vector3i in cells.keys():
		if pos.z == floor_idx:
			var belief: CellBeliefData = cells[pos] as CellBeliefData
			snapshot[Vector2i(pos.x, pos.y)] = belief.to_visual_state()
	return snapshot
