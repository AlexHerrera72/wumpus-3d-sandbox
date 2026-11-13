class_name WorldTruthData
extends RefCounted
## Capa de Datos Puros: WorldTruthData
## Contiene el estado real ("Ground Truth") del tablero N x N que el usuario edita
## en Modo Dios y que el agente desconoce inicialmente.

var grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var pits: Dictionary = {} # Vector2i -> bool
var walls: Dictionary = {} # Vector2i -> bool
var wumpus_pos: Vector2i = Vector2i(-1, -1)
var wumpus_alive: bool = true
var gold_pos: Vector2i = Vector2i(4, 4)
var gold_collected: bool = false

func _init(initial_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE) -> void:
	setup_default_scenario(initial_size)

func is_within_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y

func setup_default_scenario(new_size: Vector2i) -> void:
	grid_size = Vector2i(
		clampi(new_size.x, GameConstants.MIN_GRID_SIZE.x, GameConstants.MAX_GRID_SIZE.x),
		clampi(new_size.y, GameConstants.MIN_GRID_SIZE.y, GameConstants.MAX_GRID_SIZE.y)
	)
	pits.clear()
	walls.clear()
	wumpus_alive = true
	gold_collected = false

	if grid_size.x >= 6 and grid_size.y >= 6:
		pits[Vector2i(2, 0)] = true
		pits[Vector2i(2, 3)] = true
		pits[Vector2i(4, 2)] = true
		walls[Vector2i(1, 2)] = true
		walls[Vector2i(3, 4)] = true
		wumpus_pos = Vector2i(0, 3)
		gold_pos = Vector2i(4, 4)
	else:
		pits[Vector2i(2, 0)] = true
		walls[Vector2i(1, 2)] = true
		wumpus_pos = Vector2i(0, 2)
		gold_pos = Vector2i(grid_size.x - 1, grid_size.y - 1)

func get_orthogonal_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for dir: Vector2i in GameConstants.ORTHOGONAL_DIRS:
		var n: Vector2i = cell + dir
		if is_within_bounds(n):
			neighbors.append(n)
	return neighbors

func has_pit(cell: Vector2i) -> bool:
	return pits.get(cell, false) == true

func has_wall(cell: Vector2i) -> bool:
	return walls.get(cell, false) == true

func has_live_wumpus(cell: Vector2i) -> bool:
	return wumpus_alive and wumpus_pos == cell

func has_wumpus_corpse(cell: Vector2i) -> bool:
	return (not wumpus_alive) and wumpus_pos == cell

func has_uncollected_gold(cell: Vector2i) -> bool:
	return (not gold_collected) and gold_pos == cell

func sample_percepts_at(cell: Vector2i) -> Dictionary:
	var has_breeze: bool = false
	var has_stench: bool = false
	for neighbor: Vector2i in get_orthogonal_neighbors(cell):
		if has_pit(neighbor):
			has_breeze = true
		if has_live_wumpus(neighbor):
			has_stench = true

	var has_glitter: bool = has_uncollected_gold(cell)
	return {
		"breeze": has_breeze,
		"stench": has_stench,
		"glitter": has_glitter,
		"is_wall": has_wall(cell),
		"has_pit": has_pit(cell),
		"has_live_wumpus": has_live_wumpus(cell),
		"has_gold": has_glitter
	}

func apply_god_tool(cell: Vector2i, tool: GameConstants.GodTool, agent_pos: Vector2i) -> Dictionary:
	if not is_within_bounds(cell):
		return {"changed": false, "reason": "Celda fuera de los limites del tablero."}

	# Validacion de seguridad del Modo Dios (Seccion 1.3)
	if tool in [GameConstants.GodTool.TOGGLE_PIT, GameConstants.GodTool.TOGGLE_WALL, GameConstants.GodTool.TOGGLE_WUMPUS]:
		if cell == Vector2i.ZERO:
			return {"changed": false, "reason": "Restriccion Modo Dios: Prohibido colocar amenazas o muros en el origen (0, 0)."}
		if cell == agent_pos:
			return {"changed": false, "reason": "Restriccion Modo Dios: Prohibido colocar amenazas o muros sobre la celda actual del agente."}

	match tool:
		GameConstants.GodTool.TOGGLE_PIT:
			if has_pit(cell):
				pits.erase(cell)
				return {"changed": true, "reason": "Pozo eliminado en %s." % [str(cell)]}
			else:
				walls.erase(cell)
				if wumpus_pos == cell:
					wumpus_pos = Vector2i(-1, -1)
				pits[cell] = true
				return {"changed": true, "reason": "Pozo colocado en %s." % [str(cell)]}

		GameConstants.GodTool.TOGGLE_WALL:
			if has_wall(cell):
				walls.erase(cell)
				return {"changed": true, "reason": "Muro eliminado en %s." % [str(cell)]}
			else:
				pits.erase(cell)
				if wumpus_pos == cell:
					wumpus_pos = Vector2i(-1, -1)
				if gold_pos == cell and not gold_collected:
					return {"changed": false, "reason": "No se puede colocar un Muro sobre el Lingote de Oro."}
				walls[cell] = true
				return {"changed": true, "reason": "Muro levantado en %s." % [str(cell)]}

		GameConstants.GodTool.TOGGLE_WUMPUS:
			if wumpus_pos == cell and wumpus_alive:
				wumpus_pos = Vector2i(-1, -1)
				return {"changed": true, "reason": "Wumpus retirado de %s." % [str(cell)]}
			else:
				pits.erase(cell)
				walls.erase(cell)
				wumpus_pos = cell
				wumpus_alive = true
				return {"changed": true, "reason": "Wumpus ubicado vivo en %s." % [str(cell)]}

		GameConstants.GodTool.MOVE_GOLD:
			if has_wall(cell) or has_pit(cell):
				return {"changed": false, "reason": "No se puede colocar el Oro dentro de un Muro o Pozo."}
			gold_pos = cell
			gold_collected = false
			return {"changed": true, "reason": "Lingote de Oro reubicado en %s." % [str(cell)]}

		GameConstants.GodTool.CLEAR_CELL:
			var modified: bool = false
			if pits.erase(cell):
				modified = true
			if walls.erase(cell):
				modified = true
			if wumpus_pos == cell:
				wumpus_pos = Vector2i(-1, -1)
				modified = true
			if modified:
				return {"changed": true, "reason": "Celda %s despejada." % [str(cell)]}
			return {"changed": false, "reason": "La celda %s ya estaba despejada." % [str(cell)]}

	return {"changed": false, "reason": "Herramienta no reconocida."}

func check_arrow_hit(from_cell: Vector2i, target_cell: Vector2i) -> bool:
	if not wumpus_alive or wumpus_pos == Vector2i(-1, -1):
		return false

	var delta: Vector2i = target_cell - from_cell
	if delta == Vector2i.ZERO:
		return false

	var step_dir: Vector2i = Vector2i(signi(delta.x), signi(delta.y))
	if step_dir.x != 0 and step_dir.y != 0:
		return false

	var cursor: Vector2i = from_cell + step_dir
	while is_within_bounds(cursor):
		if has_wall(cursor):
			return false
		if cursor == wumpus_pos:
			wumpus_alive = false
			return true
		cursor += step_dir
	return false

func to_snapshot() -> Dictionary:
	var pit_list: Array[Vector2i] = []
	for k: Vector2i in pits.keys():
		if pits[k] == true:
			pit_list.append(k)

	var wall_list: Array[Vector2i] = []
	for k: Vector2i in walls.keys():
		if walls[k] == true:
			wall_list.append(k)

	var breeze_cells: Array[Vector2i] = []
	var stench_cells: Array[Vector2i] = []
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var c: Vector2i = Vector2i(x, y)
			var p: Dictionary = sample_percepts_at(c)
			if bool(p.get("breeze", false)):
				breeze_cells.append(c)
			if bool(p.get("stench", false)):
				stench_cells.append(c)

	return {
		"grid_size": grid_size,
		"pits": pit_list,
		"walls": wall_list,
		"wumpus_pos": wumpus_pos,
		"wumpus_alive": wumpus_alive,
		"gold_pos": gold_pos,
		"gold_collected": gold_collected,
		"breeze_cells": breeze_cells,
		"stench_cells": stench_cells
	}
