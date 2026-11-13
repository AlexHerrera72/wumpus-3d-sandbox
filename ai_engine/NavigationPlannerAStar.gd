class_name NavigationPlannerAStar
extends RefCounted
## Motor de IA: NavigationPlannerAStar
## Wrapper estricto sobre AStarGrid2D que protege contra el Bug Godot #8893:
## update() SOLO se invoca una vez al dimensionar la cuadricula, nunca en runtime
## tras modificar solid o weight_scale.

var astar: AStarGrid2D = AStarGrid2D.new()
var grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE

func _init(initial_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE) -> void:
	initialize_grid(initial_size)

func initialize_grid(new_size: Vector2i) -> void:
	grid_size = new_size
	astar.region = Rect2i(Vector2i.ZERO, grid_size)
	astar.cell_size = Vector2(1.0, 1.0)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.jumping_enabled = false
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	# UNICA llamada permitida a update() al inicializar el tamano de la cuadricula (Regla 4)
	astar.update()

	# Por defecto, las celdas desconocidas comienzan con un peso intermedio o solido
	# hasta que el motor epistemico certifique su estado.
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var c: Vector2i = Vector2i(x, y)
			astar.set_point_solid(c, false)
			astar.set_point_weight_scale(c, GameConstants.WEIGHT_SUSPICIOUS)

	if is_within_bounds(Vector2i.ZERO):
		astar.set_point_solid(Vector2i.ZERO, false)
		astar.set_point_weight_scale(Vector2i.ZERO, GameConstants.WEIGHT_SAFE)

func is_within_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y

func mark_cell_safe(cell: Vector2i) -> void:
	if not is_within_bounds(cell):
		return
	astar.set_point_solid(cell, false)
	astar.set_point_weight_scale(cell, GameConstants.WEIGHT_SAFE)

func mark_cell_suspicious(cell: Vector2i) -> void:
	if not is_within_bounds(cell):
		return
	astar.set_point_solid(cell, false)
	astar.set_point_weight_scale(cell, GameConstants.WEIGHT_SUSPICIOUS)

func mark_cell_hazard_or_wall(cell: Vector2i) -> void:
	if not is_within_bounds(cell):
		return
	astar.set_point_solid(cell, true)

func mark_cell_unknown(cell: Vector2i) -> void:
	if not is_within_bounds(cell):
		return
	astar.set_point_solid(cell, true)

func compute_grid_path(from_cell: Vector2i, to_cell: Vector2i, allow_temporarily_unsolid_target: bool = false) -> Array[Vector2i]:
	if not is_within_bounds(from_cell) or not is_within_bounds(to_cell):
		return []

	var was_target_solid: bool = astar.is_point_solid(to_cell)
	if was_target_solid and not allow_temporarily_unsolid_target:
		return []

	if was_target_solid and allow_temporarily_unsolid_target:
		astar.set_point_solid(to_cell, false)

	var raw_path: PackedVector2Array = astar.get_point_path(from_cell, to_cell)

	if was_target_solid and allow_temporarily_unsolid_target:
		astar.set_point_solid(to_cell, true)

	var typed_path: Array[Vector2i] = []
	for pt: Vector2 in raw_path:
		typed_path.append(Vector2i(int(round(pt.x)), int(round(pt.y))))
	return typed_path

func compute_path_cost(path: Array[Vector2i]) -> float:
	if path.is_empty():
		return INF
	var total_cost: float = 0.0
	for i: int in range(1, path.size()):
		var step_cell: Vector2i = path[i]
		total_cost += astar.get_point_weight_scale(step_cell)
	return total_cost
