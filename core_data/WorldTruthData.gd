class_name WorldTruthData
extends RefCounted
## Capa de Datos Puros: WorldTruthData
## Almacena la verdad real de una mazmorra de hasta 5 pisos:
##   - Multiples Wumpus simultaneos y Flechas recogibles
##   - Multiples pares de Portales Azul <-> Naranja en el mismo piso
##   - Escaleras libres entre cualquier coordenada de pisos distintos (2 pasos)
##   - Oro removible en modo edicion con validacion antes de iniciar
##   - Redimensionamiento de tablero preservando celdas existentes.

var grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var floor_count: int = 1

var pits: Dictionary = {} # Vector3i -> bool
var walls: Dictionary = {} # Vector3i -> bool
var wumpuses: Dictionary = {} # Vector3i -> bool (true = vivo, false = abatido)
var map_arrows: Dictionary = {} # Vector3i -> bool
var collected_arrows: Dictionary = {} # Vector3i -> bool

var gold_pos: Vector3i = Vector3i(4, 4, 0) # (-1,-1,-1) significa sin Oro colocado
var gold_collected: bool = false

# Portales estilo Portal (Azul <-> Naranja) estrictamente en el mismo piso
var portal_pairs: Array[Dictionary] = [] # [{"blue": Vector3i, "orange": Vector3i}]
var pending_blue_portal: Vector3i = Vector3i(-1, -1, -1)

# Escaleras libres entre pisos distintos (a.z != b.z, en cualquier X,Y)
var stairs_links: Array[Dictionary] = [] # [{"a": Vector3i, "b": Vector3i}]
var pending_stairs: Vector3i = Vector3i(-1, -1, -1)

func _init(initial_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE) -> void:
	setup_default_scenario(initial_size, 1)

func is_within_bounds(cell: Vector3i) -> bool:
	return (
		cell.x >= 0 and cell.x < grid_size.x
		and cell.y >= 0 and cell.y < grid_size.y
		and cell.z >= 0 and cell.z < floor_count
	)

func setup_default_scenario(new_size: Vector2i, keep_floor_count: int = 1) -> void:
	grid_size = Vector2i(
		clampi(new_size.x, GameConstants.MIN_GRID_SIZE.x, GameConstants.MAX_GRID_SIZE.x),
		clampi(new_size.y, GameConstants.MIN_GRID_SIZE.y, GameConstants.MAX_GRID_SIZE.y)
	)
	floor_count = clampi(keep_floor_count, 1, GameConstants.MAX_FLOORS)
	pits.clear()
	walls.clear()
	wumpuses.clear()
	map_arrows.clear()
	collected_arrows.clear()
	portal_pairs.clear()
	pending_blue_portal = Vector3i(-1, -1, -1)
	stairs_links.clear()
	pending_stairs = Vector3i(-1, -1, -1)
	gold_collected = false

	if grid_size.x >= 6 and grid_size.y >= 6:
		pits[Vector3i(2, 0, 0)] = true
		pits[Vector3i(2, 3, 0)] = true
		pits[Vector3i(4, 2, 0)] = true
		walls[Vector3i(1, 2, 0)] = true
		walls[Vector3i(3, 4, 0)] = true
		wumpuses[Vector3i(0, 3, 0)] = true
		gold_pos = Vector3i(4, 4, 0)
	else:
		pits[Vector3i(2, 0, 0)] = true
		walls[Vector3i(1, 2, 0)] = true
		wumpuses[Vector3i(0, 2, 0)] = true
		gold_pos = Vector3i(grid_size.x - 1, grid_size.y - 1, 0)

func resize_preserving_cells(new_size: Vector2i) -> void:
	## Cambia el tamano del tablero SIN borrar el mapa construido.
	## Si crece, simplemente anade nuevas casillas vacias.
	## Si se reduce, recorta unicamente las celdas que queden fuera de los nuevos limites.
	grid_size = Vector2i(
		clampi(new_size.x, GameConstants.MIN_GRID_SIZE.x, GameConstants.MAX_GRID_SIZE.x),
		clampi(new_size.y, GameConstants.MIN_GRID_SIZE.y, GameConstants.MAX_GRID_SIZE.y)
	)
	_prune_out_of_bounds_from_dict(pits)
	_prune_out_of_bounds_from_dict(walls)
	_prune_out_of_bounds_from_dict(wumpuses)
	_prune_out_of_bounds_from_dict(map_arrows)
	_prune_out_of_bounds_from_dict(collected_arrows)

	if gold_pos.x >= 0 and not is_within_bounds(gold_pos):
		gold_pos = Vector3i(-1, -1, -1)
	if pending_blue_portal.x >= 0 and not is_within_bounds(pending_blue_portal):
		pending_blue_portal = Vector3i(-1, -1, -1)
	if pending_stairs.x >= 0 and not is_within_bounds(pending_stairs):
		pending_stairs = Vector3i(-1, -1, -1)

	var kept_portals: Array[Dictionary] = []
	for p: Dictionary in portal_pairs:
		if is_within_bounds(p["blue"] as Vector3i) and is_within_bounds(p["orange"] as Vector3i):
			kept_portals.append(p)
	portal_pairs = kept_portals

	var kept_stairs: Array[Dictionary] = []
	for s: Dictionary in stairs_links:
		if is_within_bounds(s["a"] as Vector3i) and is_within_bounds(s["b"] as Vector3i):
			kept_stairs.append(s)
	stairs_links = kept_stairs

func _prune_out_of_bounds_from_dict(dict: Dictionary) -> void:
	var to_remove: Array[Vector3i] = []
	for k: Vector3i in dict.keys():
		if not is_within_bounds(k):
			to_remove.append(k)
	for k: Vector3i in to_remove:
		dict.erase(k)

func reset_run_preserve_map() -> void:
	for w_pos: Vector3i in wumpuses.keys():
		wumpuses[w_pos] = true
	collected_arrows.clear()
	gold_collected = false

func add_floor() -> Dictionary:
	if floor_count >= GameConstants.MAX_FLOORS:
		return {
			"changed": false,
			"reason": "Maximo numero de pisos alcanzados (%d/%d)." % [floor_count, GameConstants.MAX_FLOORS]
		}
	floor_count += 1
	return {
		"changed": true,
		"reason": "Piso %d anadido (%d/%d)." % [floor_count, floor_count, GameConstants.MAX_FLOORS]
	}

func remove_top_floor() -> Dictionary:
	if floor_count <= 1:
		return {"changed": false, "reason": "Debe existir al menos 1 piso."}
	var removed_z: int = floor_count - 1
	floor_count -= 1

	_prune_out_of_bounds_from_dict(pits)
	_prune_out_of_bounds_from_dict(walls)
	_prune_out_of_bounds_from_dict(wumpuses)
	_prune_out_of_bounds_from_dict(map_arrows)
	_prune_out_of_bounds_from_dict(collected_arrows)

	if pending_blue_portal.z >= floor_count:
		pending_blue_portal = Vector3i(-1, -1, -1)
	if pending_stairs.z >= floor_count:
		pending_stairs = Vector3i(-1, -1, -1)
	if gold_pos.z >= floor_count:
		gold_pos = Vector3i(-1, -1, -1)

	var kept_portals: Array[Dictionary] = []
	for p: Dictionary in portal_pairs:
		if is_within_bounds(p["blue"] as Vector3i) and is_within_bounds(p["orange"] as Vector3i):
			kept_portals.append(p)
	portal_pairs = kept_portals

	var kept_stairs: Array[Dictionary] = []
	for s: Dictionary in stairs_links:
		if is_within_bounds(s["a"] as Vector3i) and is_within_bounds(s["b"] as Vector3i):
			kept_stairs.append(s)
	stairs_links = kept_stairs

	return {"changed": true, "reason": "Piso %d eliminado." % [removed_z + 1]}

func get_orthogonal_neighbors(cell: Vector3i) -> Array[Vector3i]:
	var neighbors: Array[Vector3i] = []
	for dir: Vector2i in GameConstants.ORTHOGONAL_DIRS:
		var n: Vector3i = Vector3i(cell.x + dir.x, cell.y + dir.y, cell.z)
		if is_within_bounds(n):
			neighbors.append(n)
	return neighbors

func has_pit(cell: Vector3i) -> bool:
	return pits.get(cell, false) == true

func has_wall(cell: Vector3i) -> bool:
	return walls.get(cell, false) == true

func has_live_wumpus(cell: Vector3i) -> bool:
	return wumpuses.has(cell) and bool(wumpuses[cell]) == true

func has_gold_placed() -> bool:
	return gold_pos.x >= 0 and is_within_bounds(gold_pos)

func has_uncollected_gold(cell: Vector3i) -> bool:
	return (not gold_collected) and has_gold_placed() and gold_pos == cell

func has_uncollected_arrow(cell: Vector3i) -> bool:
	return map_arrows.get(cell, false) == true and not collected_arrows.has(cell)

func collect_arrow_at(cell: Vector3i) -> bool:
	if has_uncollected_arrow(cell):
		collected_arrows[cell] = true
		return true
	return false

func has_unlinked_portal() -> bool:
	return pending_blue_portal.x >= 0 and is_within_bounds(pending_blue_portal)

func has_unlinked_stairs() -> bool:
	return pending_stairs.x >= 0 and is_within_bounds(pending_stairs)

func get_portal_color_at(cell: Vector3i) -> String:
	if pending_blue_portal == cell and pending_blue_portal.x >= 0:
		return "blue_pending"
	for p: Dictionary in portal_pairs:
		if (p["blue"] as Vector3i) == cell:
			return "blue"
		if (p["orange"] as Vector3i) == cell:
			return "orange"
	return ""

func get_linked_portal_destination(cell: Vector3i) -> Vector3i:
	for p: Dictionary in portal_pairs:
		var b: Vector3i = p["blue"] as Vector3i
		var o: Vector3i = p["orange"] as Vector3i
		if cell == b:
			return o
		if cell == o:
			return b
	return Vector3i(-1, -1, -1)

func get_stairs_destinations(cell: Vector3i) -> Array[Vector3i]:
	var dests: Array[Vector3i] = []
	for s: Dictionary in stairs_links:
		var a: Vector3i = s["a"] as Vector3i
		var b: Vector3i = s["b"] as Vector3i
		if cell == a:
			dests.append(b)
		elif cell == b:
			dests.append(a)
	return dests

func has_stairs_at(cell: Vector3i) -> bool:
	if pending_stairs == cell and pending_stairs.x >= 0:
		return true
	return not get_stairs_destinations(cell).is_empty()

func get_all_special_destinations(cell: Vector3i) -> Array[Vector3i]:
	var dests: Array[Vector3i] = []
	var p_dest: Vector3i = get_linked_portal_destination(cell)
	if p_dest.x >= 0:
		dests.append(p_dest)
	for st_dest: Vector3i in get_stairs_destinations(cell):
		dests.append(st_dest)
	return dests

func sample_percepts_at(cell: Vector3i) -> Dictionary:
	var has_breeze: bool = false
	var has_stench: bool = false
	var adjacent_walls: Array[Vector3i] = []
	for neighbor: Vector3i in get_orthogonal_neighbors(cell):
		if has_wall(neighbor):
			adjacent_walls.append(neighbor)
		if has_pit(neighbor):
			has_breeze = true
		if has_live_wumpus(neighbor):
			has_stench = true

	var has_glitter: bool = has_uncollected_gold(cell)
	var special_dests: Array[Vector3i] = get_all_special_destinations(cell)
	return {
		"breeze": has_breeze,
		"stench": has_stench,
		"glitter": has_glitter,
		"is_wall": has_wall(cell),
		"adjacent_walls": adjacent_walls,
		"has_pit": has_pit(cell),
		"has_live_wumpus": has_live_wumpus(cell),
		"has_gold": has_glitter,
		"has_arrow_pickup": has_uncollected_arrow(cell),
		"special_destinations": special_dests
	}

func apply_god_tool(cell: Vector3i, tool: GameConstants.GodTool, agent_pos: Vector3i) -> Dictionary:
	if not is_within_bounds(cell):
		return {"changed": false, "reason": "Celda fuera de limites."}

	if tool in [GameConstants.GodTool.TOGGLE_PIT, GameConstants.GodTool.TOGGLE_WALL, GameConstants.GodTool.TOGGLE_WUMPUS]:
		if cell == Vector3i(0, 0, 0):
			return {"changed": false, "reason": "Prohibido colocar amenazas o muros en (0, 0, P1)."}
		if cell == agent_pos:
			return {"changed": false, "reason": "Prohibido colocar amenazas o muros sobre el agente."}

	match tool:
		GameConstants.GodTool.TOGGLE_PIT:
			if has_pit(cell):
				pits.erase(cell)
				return {"changed": true, "reason": "Pozo eliminado en %s." % [_fmt_cell(cell)]}
			else:
				_remove_portal_or_stairs_at(cell)
				walls.erase(cell)
				wumpuses.erase(cell)
				map_arrows.erase(cell)
				if gold_pos == cell:
					gold_pos = Vector3i(-1, -1, -1)
				pits[cell] = true
				return {"changed": true, "reason": "Pozo colocado en %s." % [_fmt_cell(cell)]}

		GameConstants.GodTool.TOGGLE_WALL:
			if has_wall(cell):
				walls.erase(cell)
				return {"changed": true, "reason": "Muro eliminado en %s." % [_fmt_cell(cell)]}
			else:
				if gold_pos == cell and not gold_collected:
					return {"changed": false, "reason": "Quita primero el Oro antes de colocar un Muro."}
				_remove_portal_or_stairs_at(cell)
				pits.erase(cell)
				wumpuses.erase(cell)
				map_arrows.erase(cell)
				walls[cell] = true
				return {"changed": true, "reason": "Muro levantado en %s." % [_fmt_cell(cell)]}

		GameConstants.GodTool.TOGGLE_WUMPUS:
			if wumpuses.has(cell):
				wumpuses.erase(cell)
				return {"changed": true, "reason": "Wumpus retirado de %s." % [_fmt_cell(cell)]}
			else:
				pits.erase(cell)
				walls.erase(cell)
				wumpuses[cell] = true
				return {"changed": true, "reason": "Wumpus colocado en %s." % [_fmt_cell(cell)]}

		GameConstants.GodTool.MOVE_GOLD:
			# Permitir quitar el oro si se hace clic donde ya esta
			if gold_pos == cell:
				gold_pos = Vector3i(-1, -1, -1)
				gold_collected = false
				return {"changed": true, "reason": "Oro retirado del mapa."}
			if has_wall(cell) or has_pit(cell):
				return {"changed": false, "reason": "No se puede colocar el Oro sobre un Muro o Pozo."}
			gold_pos = cell
			gold_collected = false
			return {"changed": true, "reason": "Oro colocado en %s." % [_fmt_cell(cell)]}

		GameConstants.GodTool.TOGGLE_PORTAL:
			var existing_col: String = get_portal_color_at(cell)
			if not existing_col.is_empty():
				_remove_portal_at(cell)
				return {"changed": true, "reason": "Portal retirado de %s." % [_fmt_cell(cell)]}
			if cell == Vector3i(0, 0, 0):
				return {"changed": false, "reason": "No se puede colocar un Portal en (0, 0, P1)."}
			if has_wall(cell) or has_pit(cell) or has_stairs_at(cell):
				return {"changed": false, "reason": "Casilla ocupada por Muro, Pozo o Escalera."}

			if pending_blue_portal.x < 0:
				pending_blue_portal = cell
				return {
					"changed": true,
					"reason": "Portal AZUL en %s. Coloca el NARANJA en P%d." % [_fmt_cell(cell), cell.z + 1]
				}
			else:
				if cell.z != pending_blue_portal.z:
					return {
						"changed": false,
						"reason": "El Portal NARANJA debe ir en el mismo piso (P%d). Usa Escaleras para otros pisos." % [pending_blue_portal.z + 1]
					}
				portal_pairs.append({"blue": pending_blue_portal, "orange": cell})
				var b_str: String = _fmt_cell(pending_blue_portal)
				pending_blue_portal = Vector3i(-1, -1, -1)
				return {
					"changed": true,
					"reason": "Portales vinculados: AZUL %s <-> NARANJA %s." % [b_str, _fmt_cell(cell)]
				}

		GameConstants.GodTool.TOGGLE_STAIRS:
			if floor_count < 2:
				return {"changed": false, "reason": "Anade al menos un 2do piso para colocar Escaleras."}
			if has_stairs_at(cell):
				_remove_stairs_at(cell)
				return {"changed": true, "reason": "Escalera retirada en %s." % [_fmt_cell(cell)]}
			if cell == Vector3i(0, 0, 0):
				return {"changed": false, "reason": "No se puede colocar una Escalera en (0, 0, P1)."}
			if has_wall(cell) or has_pit(cell) or not get_portal_color_at(cell).is_empty():
				return {"changed": false, "reason": "Casilla ocupada por Muro, Pozo o Portal."}

			if pending_stairs.x < 0:
				pending_stairs = cell
				return {
					"changed": true,
					"reason": "Escalera iniciada en %s. Cambia de piso y elige donde conectarla." % [_fmt_cell(cell)]
				}
			else:
				if cell.z == pending_stairs.z:
					return {
						"changed": false,
						"reason": "Las Escaleras deben conectar pisos distintos. Cambia de piso para terminar la escalera."
					}
				stairs_links.append({"a": pending_stairs, "b": cell})
				var a_str: String = _fmt_cell(pending_stairs)
				pending_stairs = Vector3i(-1, -1, -1)
				return {
					"changed": true,
					"reason": "Escalera conectada: %s <-> %s." % [a_str, _fmt_cell(cell)]
				}

		GameConstants.GodTool.TOGGLE_ARROW:
			if map_arrows.has(cell):
				map_arrows.erase(cell)
				collected_arrows.erase(cell)
				return {"changed": true, "reason": "Flecha retirada de %s." % [_fmt_cell(cell)]}
			if has_wall(cell) or has_pit(cell):
				return {"changed": false, "reason": "No se puede colocar una Flecha sobre un Muro o Pozo."}
			map_arrows[cell] = true
			collected_arrows.erase(cell)
			return {"changed": true, "reason": "Flecha colocada en %s." % [_fmt_cell(cell)]}

		GameConstants.GodTool.CLEAR_CELL:
			var modified: bool = false
			if pits.erase(cell):
				modified = true
			if walls.erase(cell):
				modified = true
			if wumpuses.erase(cell):
				modified = true
			if map_arrows.erase(cell):
				collected_arrows.erase(cell)
				modified = true
			if gold_pos == cell:
				gold_pos = Vector3i(-1, -1, -1)
				gold_collected = false
				modified = true
			if _remove_portal_or_stairs_at(cell):
				modified = true
			if modified:
				return {"changed": true, "reason": "Objeto eliminado en %s." % [_fmt_cell(cell)]}
			return {"changed": false, "reason": ""}

	return {"changed": false, "reason": ""}

func _remove_portal_at(cell: Vector3i) -> bool:
	var removed: bool = false
	if pending_blue_portal == cell:
		pending_blue_portal = Vector3i(-1, -1, -1)
		removed = true
	var kept: Array[Dictionary] = []
	for p: Dictionary in portal_pairs:
		if (p["blue"] as Vector3i) == cell or (p["orange"] as Vector3i) == cell:
			removed = true
		else:
			kept.append(p)
	portal_pairs = kept
	return removed

func _remove_stairs_at(cell: Vector3i) -> bool:
	var removed: bool = false
	if pending_stairs == cell:
		pending_stairs = Vector3i(-1, -1, -1)
		removed = true
	var kept: Array[Dictionary] = []
	for s: Dictionary in stairs_links:
		if (s["a"] as Vector3i) == cell or (s["b"] as Vector3i) == cell:
			removed = true
		else:
			kept.append(s)
	stairs_links = kept
	return removed

func _remove_portal_or_stairs_at(cell: Vector3i) -> bool:
	var r1: bool = _remove_portal_at(cell)
	var r2: bool = _remove_stairs_at(cell)
	return r1 or r2

func check_arrow_hit(from_cell: Vector3i, target_cell: Vector3i) -> Dictionary:
	if from_cell.z != target_cell.z:
		return {"hit": false, "hit_cell": Vector3i(-1, -1, -1)}

	var delta: Vector2i = Vector2i(target_cell.x - from_cell.x, target_cell.y - from_cell.y)
	if delta == Vector2i.ZERO:
		return {"hit": false, "hit_cell": Vector3i(-1, -1, -1)}

	var step_dir: Vector2i = Vector2i(signi(delta.x), signi(delta.y))
	if step_dir.x != 0 and step_dir.y != 0:
		return {"hit": false, "hit_cell": Vector3i(-1, -1, -1)}

	var cursor: Vector3i = Vector3i(from_cell.x + step_dir.x, from_cell.y + step_dir.y, from_cell.z)
	while is_within_bounds(cursor):
		if has_wall(cursor):
			return {"hit": false, "hit_cell": Vector3i(-1, -1, -1)}
		if has_live_wumpus(cursor):
			wumpuses[cursor] = false
			return {"hit": true, "hit_cell": cursor}
		cursor = Vector3i(cursor.x + step_dir.x, cursor.y + step_dir.y, cursor.z)
	return {"hit": false, "hit_cell": Vector3i(-1, -1, -1)}

func _fmt_cell(c: Vector3i) -> String:
	return "(%d,%d,P%d)" % [c.x, c.y, c.z + 1]

func serialize_to_dict() -> Dictionary:
	var pit_arr: Array[Array] = []
	for k: Vector3i in pits.keys():
		if pits[k] == true:
			pit_arr.append([k.x, k.y, k.z])
	var wall_arr: Array[Array] = []
	for k: Vector3i in walls.keys():
		if walls[k] == true:
			wall_arr.append([k.x, k.y, k.z])
	var wump_arr: Array[Array] = []
	for k: Vector3i in wumpuses.keys():
		wump_arr.append([k.x, k.y, k.z])
	var arrow_arr: Array[Array] = []
	for k: Vector3i in map_arrows.keys():
		if map_arrows[k] == true:
			arrow_arr.append([k.x, k.y, k.z])
	var p_pairs_arr: Array[Dictionary] = []
	for p: Dictionary in portal_pairs:
		var b: Vector3i = p["blue"] as Vector3i
		var o: Vector3i = p["orange"] as Vector3i
		p_pairs_arr.append({"blue": [b.x, b.y, b.z], "orange": [o.x, o.y, o.z]})
	var st_arr: Array[Dictionary] = []
	for s: Dictionary in stairs_links:
		var a: Vector3i = s["a"] as Vector3i
		var b: Vector3i = s["b"] as Vector3i
		st_arr.append({"a": [a.x, a.y, a.z], "b": [b.x, b.y, b.z]})

	return {
		"grid_size": [grid_size.x, grid_size.y],
		"floor_count": floor_count,
		"pits": pit_arr,
		"walls": wall_arr,
		"wumpuses": wump_arr,
		"map_arrows": arrow_arr,
		"gold_pos": [gold_pos.x, gold_pos.y, gold_pos.z],
		"portal_pairs": p_pairs_arr,
		"stairs_links": st_arr
	}

func deserialize_from_dict(data: Dictionary) -> bool:
	if not data.has("grid_size"):
		return false
	var gs: Array = data.get("grid_size", [6, 6])
	if gs.size() < 2:
		return false

	grid_size = Vector2i(
		clampi(int(gs[0]), GameConstants.MIN_GRID_SIZE.x, GameConstants.MAX_GRID_SIZE.x),
		clampi(int(gs[1]), GameConstants.MIN_GRID_SIZE.y, GameConstants.MAX_GRID_SIZE.y)
	)
	floor_count = clampi(int(data.get("floor_count", 1)), 1, GameConstants.MAX_FLOORS)
	pits.clear()
	walls.clear()
	wumpuses.clear()
	map_arrows.clear()
	collected_arrows.clear()
	portal_pairs.clear()
	pending_blue_portal = Vector3i(-1, -1, -1)
	stairs_links.clear()
	pending_stairs = Vector3i(-1, -1, -1)

	for item: Variant in data.get("pits", []):
		var c: Vector3i = _parse_vec3i(item)
		if is_within_bounds(c):
			pits[c] = true
	for item: Variant in data.get("walls", []):
		var c: Vector3i = _parse_vec3i(item)
		if is_within_bounds(c):
			walls[c] = true
	for item: Variant in data.get("wumpuses", []):
		var c: Vector3i = _parse_vec3i(item)
		if is_within_bounds(c):
			wumpuses[c] = true
	if data.has("wumpus_pos") and wumpuses.is_empty():
		var legacy_w: Vector3i = _parse_vec3i(data.get("wumpus_pos", [-1, -1, -1]))
		if is_within_bounds(legacy_w):
			wumpuses[legacy_w] = true

	for item: Variant in data.get("map_arrows", []):
		var c: Vector3i = _parse_vec3i(item)
		if is_within_bounds(c):
			map_arrows[c] = true

	for item: Variant in data.get("portal_pairs", []):
		if item is Dictionary:
			var d: Dictionary = item as Dictionary
			var b: Vector3i = _parse_vec3i(d.get("blue", [-1, -1, -1]))
			var o: Vector3i = _parse_vec3i(d.get("orange", [-1, -1, -1]))
			if is_within_bounds(b) and is_within_bounds(o) and b.z == o.z and b != o:
				portal_pairs.append({"blue": b, "orange": o})

	for item: Variant in data.get("stairs_links", []):
		if item is Dictionary:
			var d: Dictionary = item as Dictionary
			var a: Vector3i = _parse_vec3i(d.get("a", d.get("lower", [-1, -1, -1])))
			var b: Vector3i = _parse_vec3i(d.get("b", d.get("upper", [-1, -1, -1])))
			if is_within_bounds(a) and is_within_bounds(b) and a.z != b.z:
				stairs_links.append({"a": a, "b": b})

	gold_pos = _parse_vec3i(data.get("gold_pos", [-1, -1, -1]))
	if gold_pos.x >= 0 and not is_within_bounds(gold_pos):
		gold_pos = Vector3i(-1, -1, -1)
	gold_collected = false
	return true

func _parse_vec3i(raw: Variant) -> Vector3i:
	if raw is Array and (raw as Array).size() >= 3:
		var a: Array = raw as Array
		return Vector3i(int(a[0]), int(a[1]), int(a[2]))
	return Vector3i(-1, -1, -1)

func to_snapshot() -> Dictionary:
	var pit_list: Array[Vector3i] = []
	for k: Vector3i in pits.keys():
		if pits[k] == true:
			pit_list.append(k)

	var wall_list: Array[Vector3i] = []
	for k: Vector3i in walls.keys():
		if walls[k] == true:
			wall_list.append(k)

	var arrow_list: Array[Vector3i] = []
	for k: Vector3i in map_arrows.keys():
		if has_uncollected_arrow(k):
			arrow_list.append(k)

	var portal_colors: Dictionary = {}
	if pending_blue_portal.x >= 0:
		portal_colors[pending_blue_portal] = "blue_pending"
	for p: Dictionary in portal_pairs:
		portal_colors[p["blue"] as Vector3i] = "blue"
		portal_colors[p["orange"] as Vector3i] = "orange"

	var stairs_up_cells: Dictionary = {}
	var stairs_down_cells: Dictionary = {}
	var stairs_pending_cells: Dictionary = {}
	if pending_stairs.x >= 0:
		stairs_pending_cells[pending_stairs] = true
	for s: Dictionary in stairs_links:
		var a: Vector3i = s["a"] as Vector3i
		var b: Vector3i = s["b"] as Vector3i
		if a.z < b.z:
			stairs_up_cells[a] = true
			stairs_down_cells[b] = true
		else:
			stairs_up_cells[b] = true
			stairs_down_cells[a] = true

	var breeze_cells: Array[Vector3i] = []
	var stench_cells: Array[Vector3i] = []
	for fl: int in range(floor_count):
		for y: int in range(grid_size.y):
			for x: int in range(grid_size.x):
				var c: Vector3i = Vector3i(x, y, fl)
				var p: Dictionary = sample_percepts_at(c)
				if bool(p.get("breeze", false)):
					breeze_cells.append(c)
				if bool(p.get("stench", false)):
					stench_cells.append(c)

	return {
		"grid_size": grid_size,
		"floor_count": floor_count,
		"pits": pit_list,
		"walls": wall_list,
		"wumpuses": wumpuses.duplicate(),
		"arrows": arrow_list,
		"gold_pos": gold_pos,
		"gold_collected": gold_collected,
		"portal_colors": portal_colors,
		"stairs_up": stairs_up_cells,
		"stairs_down": stairs_down_cells,
		"stairs_pending": stairs_pending_cells,
		"breeze_cells": breeze_cells,
		"stench_cells": stench_cells
	}
