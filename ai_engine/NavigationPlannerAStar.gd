class_name NavigationPlannerAStar
extends RefCounted
## Motor de IA: NavigationPlannerAStar
## Mantiene dos arreglos de AStarGrid2D por piso (hasta 5 pisos):
##   - astar_safe_floors: SOLO celdas SAFE son transitables (garantiza rodeos
##     100% seguros por largos que sean sin cortar por celdas sospechosas).
##   - astar_risk_floors: Permite celdas SUSPICIOUS con peso 25.0 (solo usado
##     cuando ya no existe ninguna celda SAFE alcanzable).
## Protege estrictamente contra Bug Godot #8893 (update() una sola vez al crear).
## Soporta rutas multi-salto encadenadas por Escaleras entre pisos y Portales.

var astar_safe_floors: Array[AStarGrid2D] = []
var astar_risk_floors: Array[AStarGrid2D] = []
var grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var floor_count: int = 1

func _init(initial_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE, initial_floors: int = 1) -> void:
	initialize_grid(initial_size, initial_floors)

func initialize_grid(new_size: Vector2i, new_floor_count: int = 1) -> void:
	grid_size = new_size
	floor_count = clampi(new_floor_count, 1, GameConstants.MAX_FLOORS)
	astar_safe_floors.clear()
	astar_risk_floors.clear()

	for fl: int in range(floor_count):
		var a_safe: AStarGrid2D = _create_single_floor_astar(fl)
		var a_risk: AStarGrid2D = _create_single_floor_astar(fl)
		astar_safe_floors.append(a_safe)
		astar_risk_floors.append(a_risk)

func _create_single_floor_astar(floor_idx: int) -> AStarGrid2D:
	var astar: AStarGrid2D = AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, grid_size)
	astar.cell_size = Vector2(1.0, 1.0)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.jumping_enabled = false
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	# UNICA llamada permitida a update() al inicializar el piso (Regla 4)
	astar.update()

	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var c2: Vector2i = Vector2i(x, y)
			astar.set_point_solid(c2, true)
			astar.set_point_weight_scale(c2, GameConstants.WEIGHT_SUSPICIOUS)

	if floor_idx == 0 and grid_size.x > 0 and grid_size.y > 0:
		astar.set_point_solid(Vector2i.ZERO, false)
		astar.set_point_weight_scale(Vector2i.ZERO, GameConstants.WEIGHT_SAFE)

	return astar

func is_within_bounds(cell: Vector3i) -> bool:
	return (
		cell.x >= 0 and cell.x < grid_size.x
		and cell.y >= 0 and cell.y < grid_size.y
		and cell.z >= 0 and cell.z < floor_count
	)

func mark_cell_safe(cell: Vector3i) -> void:
	if not is_within_bounds(cell):
		return
	var c2: Vector2i = Vector2i(cell.x, cell.y)
	astar_safe_floors[cell.z].set_point_solid(c2, false)
	astar_safe_floors[cell.z].set_point_weight_scale(c2, GameConstants.WEIGHT_SAFE)
	astar_risk_floors[cell.z].set_point_solid(c2, false)
	astar_risk_floors[cell.z].set_point_weight_scale(c2, GameConstants.WEIGHT_SAFE)

func mark_cell_suspicious(cell: Vector3i) -> void:
	if not is_within_bounds(cell):
		return
	var c2: Vector2i = Vector2i(cell.x, cell.y)
	# En el grafo estrictamente seguro, las celdas sospechosas son IMPASABLES
	astar_safe_floors[cell.z].set_point_solid(c2, true)
	# En el grafo de riesgo controlado, son pasables con penalizacion 25.0
	astar_risk_floors[cell.z].set_point_solid(c2, false)
	astar_risk_floors[cell.z].set_point_weight_scale(c2, GameConstants.WEIGHT_SUSPICIOUS)

func mark_cell_low_risk_explained(cell: Vector3i) -> void:
	## Celda cuya brisa/hedor adyacente ya fue explicada por un peligro confirmado:
	## mantiene riesgo residual (posible pozo contiguo), por lo que sigue bloqueada
	## en safe-only, pero tiene mucho menor costo (8.0 vs 25.0) en el grafo de riesgo.
	if not is_within_bounds(cell):
		return
	var c2: Vector2i = Vector2i(cell.x, cell.y)
	astar_safe_floors[cell.z].set_point_solid(c2, true)
	astar_risk_floors[cell.z].set_point_solid(c2, false)
	astar_risk_floors[cell.z].set_point_weight_scale(c2, 8.0)

func mark_cell_hazard_or_wall(cell: Vector3i) -> void:
	if not is_within_bounds(cell):
		return
	var c2: Vector2i = Vector2i(cell.x, cell.y)
	astar_safe_floors[cell.z].set_point_solid(c2, true)
	astar_risk_floors[cell.z].set_point_solid(c2, true)

func mark_cell_unknown(cell: Vector3i) -> void:
	if not is_within_bounds(cell):
		return
	var c2: Vector2i = Vector2i(cell.x, cell.y)
	astar_safe_floors[cell.z].set_point_solid(c2, true)
	astar_risk_floors[cell.z].set_point_solid(c2, true)

func _compute_same_floor_path(from_cell: Vector3i, to_cell: Vector3i, strict_safe_only: bool) -> Array[Vector3i]:
	if from_cell.z != to_cell.z or not is_within_bounds(from_cell) or not is_within_bounds(to_cell):
		return []
	if from_cell == to_cell:
		return [from_cell]

	var astar: AStarGrid2D = astar_safe_floors[from_cell.z] if strict_safe_only else astar_risk_floors[from_cell.z]
	var from_2d: Vector2i = Vector2i(from_cell.x, from_cell.y)
	var to_2d: Vector2i = Vector2i(to_cell.x, to_cell.y)
	if astar.is_point_solid(to_2d):
		return []

	var raw_path: PackedVector2Array = astar.get_point_path(from_2d, to_2d)
	var typed_path: Array[Vector3i] = []
	for pt: Vector2 in raw_path:
		typed_path.append(Vector3i(int(round(pt.x)), int(round(pt.y)), from_cell.z))
	return typed_path

func compute_grid_path_3d(
	from_cell: Vector3i,
	to_cell: Vector3i,
	special_links: Array[Array],
	strict_safe_only: bool = true
) -> Array[Vector3i]:
	## Calcula la ruta optima multipiso encadenando multiples Escaleras y Portales
	## mediante Dijkstra sobre el grafo de portales/escaleras + AStarGrid2D local.
	if not is_within_bounds(from_cell) or not is_within_bounds(to_cell):
		return []
	if from_cell == to_cell:
		return [from_cell]

	# Caso rapido: sin enlaces especiales, solo mismo piso
	if special_links.is_empty():
		if from_cell.z != to_cell.z:
			return []
		return _compute_same_floor_path(from_cell, to_cell, strict_safe_only)

	# Construir conjunto de nodos clave: from_cell, to_cell y extremos de portales/escaleras
	var nodes: Array[Vector3i] = [from_cell]
	if not nodes.has(to_cell):
		nodes.append(to_cell)
	for link: Array in special_links:
		if link.size() >= 2:
			var a: Vector3i = link[0] as Vector3i
			var b: Vector3i = link[1] as Vector3i
			if is_within_bounds(a) and not nodes.has(a):
				nodes.append(a)
			if is_within_bounds(b) and not nodes.has(b):
				nodes.append(b)

	var n_count: int = nodes.size()
	var target_idx: int = nodes.find(to_cell)
	if target_idx == -1:
		return []

	var dist: Array[float] = []
	var visited_node: Array[bool] = []
	var prev_node: Array[int] = []
	var prev_segment: Array[Array] = [] # Array[Vector3i] para reconstruir la ruta exacta
	for i: int in range(n_count):
		dist.append(INF)
		visited_node.append(false)
		prev_node.append(-1)
		prev_segment.append([])

	dist[0] = 0.0

	for _iter: int in range(n_count):
		var u: int = -1
		var best_d: float = INF
		for i: int in range(n_count):
			if not visited_node[i] and dist[i] < best_d:
				best_d = dist[i]
				u = i
		if u == -1 or u == target_idx:
			break
		visited_node[u] = true
		var u_cell: Vector3i = nodes[u]

		# 1. Aristas especiales (Portales y Escaleras, costo 1.0)
		for link: Array in special_links:
			if link.size() < 2:
				continue
			var a: Vector3i = link[0] as Vector3i
			var b: Vector3i = link[1] as Vector3i
			var dest: Vector3i = Vector3i(-1, -1, -1)
			if u_cell == a:
				dest = b
			elif u_cell == b:
				dest = a
			if dest.x >= 0:
				var v: int = nodes.find(dest)
				if v != -1 and not visited_node[v]:
					var astar_v: AStarGrid2D = astar_safe_floors[dest.z] if strict_safe_only else astar_risk_floors[dest.z]
					if not astar_v.is_point_solid(Vector2i(dest.x, dest.y)):
						var alt: float = dist[u] + 1.0
						if alt < dist[v]:
							dist[v] = alt
							prev_node[v] = u
							prev_segment[v] = [u_cell, dest]

		# 2. Aristas intra-piso via AStarGrid2D
		for v: int in range(n_count):
			if visited_node[v] or v == u:
				continue
			var v_cell: Vector3i = nodes[v]
			if v_cell.z != u_cell.z:
				continue
			var seg: Array[Vector3i] = _compute_same_floor_path(u_cell, v_cell, strict_safe_only)
			if seg.is_empty():
				continue
			var seg_cost: float = compute_path_cost_3d(seg, strict_safe_only)
			var alt_d: float = dist[u] + seg_cost
			if alt_d < dist[v]:
				dist[v] = alt_d
				prev_node[v] = u
				prev_segment[v] = seg

	if dist[target_idx] == INF:
		return []

	# Reconstruir ruta completa encadenando los tramos
	var segments_reversed: Array[Array] = []
	var cur: int = target_idx
	while cur != -1 and prev_node[cur] != -1:
		segments_reversed.append(prev_segment[cur])
		cur = prev_node[cur]

	var full_path: Array[Vector3i] = [from_cell]
	for idx: int in range(segments_reversed.size() - 1, -1, -1):
		var seg_arr: Array = segments_reversed[idx]
		for s_i: int in range(1, seg_arr.size()):
			full_path.append(seg_arr[s_i] as Vector3i)
	return full_path

func compute_path_cost_3d(path: Array[Vector3i], strict_safe_only: bool = false) -> float:
	if path.is_empty():
		return INF
	var total_cost: float = 0.0
	for i: int in range(1, path.size()):
		var step_cell: Vector3i = path[i]
		if not is_within_bounds(step_cell):
			return INF
		var astar: AStarGrid2D = astar_safe_floors[step_cell.z] if strict_safe_only else astar_risk_floors[step_cell.z]
		total_cost += astar.get_point_weight_scale(Vector2i(step_cell.x, step_cell.y))
	return total_cost
