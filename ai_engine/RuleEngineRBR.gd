class_name RuleEngineRBR
extends RefCounted
## Motor de IA: RuleEngineRBR
## Sistema Experto Basado en Reglas (Forward Chaining de Punto Fijo).
## Evalua las 8 Reglas de Produccion (R1 a R8), sincroniza pesos en AStarGrid2D
## y emite trazabilidad explicable (XAI) mediante EventBus.

var _announced_keys: Dictionary = {} # String -> bool

func clear_announced_history() -> void:
	_announced_keys.clear()

func _emit_xai_once(turn_number: int, rule_code: String, ded_key: String, message: String) -> void:
	if _announced_keys.has(ded_key):
		return
	_announced_keys[ded_key] = true
	EventBus.xai_rule_triggered.emit(turn_number, rule_code, message)

func run_forward_chaining(
	epistemic_map: EpistemicMapData,
	nav_planner: NavigationPlannerAStar,
	world_truth: WorldTruthData,
	turn_number: int
) -> Dictionary:
	var confirmed_wumpus_cell: Vector2i = Vector2i(-1, -1)
	var arrow_shot_performed: bool = false
	var arrow_target_cell: Vector2i = Vector2i(-1, -1)
	var arrow_hit_success: bool = false

	# Primero bloqueamos en AStar todas las celdas que sean muros conocidos o no visitadas desconocidas
	for pos: Vector2i in epistemic_map.cells.keys():
		var c_init: CellBeliefData = epistemic_map.get_cell(pos)
		if c_init.is_wall:
			c_init.overall_state = GameConstants.OverallState.CONFIRMED_HAZARD
			nav_planner.mark_cell_hazard_or_wall(pos)
		elif c_init.visited:
			c_init.pit_state = GameConstants.FactState.SAFE
			c_init.wumpus_state = GameConstants.FactState.SAFE
			c_init.overall_state = GameConstants.OverallState.SAFE
			nav_planner.mark_cell_safe(pos)
		else:
			nav_planner.mark_cell_unknown(pos)

	# Bucle de Punto Fijo (Forward Chaining R1 a R6)
	var deduction_made: bool = true
	var iteration_guard: int = 0
	while deduction_made and iteration_guard < 64:
		deduction_made = false
		iteration_guard += 1

		# Regla R1 (Descarte de Pozo) y Regla R2 (Descarte de Wumpus)
		for v_pos: Vector2i in epistemic_map.visited_cells:
			var v_cell: CellBeliefData = epistemic_map.get_cell(v_pos)
			if v_cell == null or not v_cell.visited:
				continue

			var neighbors: Array[Vector2i] = epistemic_map.get_passable_orthogonal_neighbors(v_pos)

			# Regla R1: SI visited(x,y) == true Y breeze(x,y) == false -> vecinos pit_state = SAFE
			if not v_cell.breeze:
				for n_pos: Vector2i in neighbors:
					var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
					if n_cell.pit_state != GameConstants.FactState.SAFE:
						n_cell.pit_state = GameConstants.FactState.SAFE
						deduction_made = true
						_emit_xai_once(
							turn_number,
							"R1",
							"R1_%s" % [str(n_pos)],
							"Ausencia de brisa en %s descarta Pozo en vecino %s." % [str(v_pos), str(n_pos)]
						)

			# Regla R2: SI visited(x,y) == true Y (stench(x,y) == false O wumpus_killed == true) -> vecinos wumpus_state = SAFE
			if (not v_cell.stench) or epistemic_map.wumpus_killed:
				for n_pos: Vector2i in neighbors:
					var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
					if n_cell.wumpus_state != GameConstants.FactState.SAFE:
						n_cell.wumpus_state = GameConstants.FactState.SAFE
						deduction_made = true
						_emit_xai_once(
							turn_number,
							"R2",
							"R2_%s" % [str(n_pos)],
							"Ausencia de hedor en %s descarta Wumpus en vecino %s." % [str(v_pos), str(n_pos)]
						)

		# Regla R4 (Propagacion de Sospecha y Penalizacion Heuristica)
		for v_pos: Vector2i in epistemic_map.visited_cells:
			var v_cell: CellBeliefData = epistemic_map.get_cell(v_pos)
			if v_cell == null or not v_cell.visited:
				continue
			if not v_cell.breeze and not v_cell.stench:
				continue

			for n_pos: Vector2i in epistemic_map.get_passable_orthogonal_neighbors(v_pos):
				var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
				if n_cell.visited:
					continue

				if v_cell.breeze and n_cell.pit_state == GameConstants.FactState.UNKNOWN:
					n_cell.pit_state = GameConstants.FactState.SUSPICIOUS
					deduction_made = true
					_emit_xai_once(
						turn_number,
						"R4",
						"R4_PIT_%s" % [str(n_pos)],
						"Brisa percibida en %s marca %s como SOSPECHOSA de Pozo (peso A* = 25.0)." % [str(v_pos), str(n_pos)]
					)

				if v_cell.stench and (not epistemic_map.wumpus_killed) and n_cell.wumpus_state == GameConstants.FactState.UNKNOWN:
					n_cell.wumpus_state = GameConstants.FactState.SUSPICIOUS
					deduction_made = true
					_emit_xai_once(
						turn_number,
						"R4",
						"R4_WUMPUS_%s" % [str(n_pos)],
						"Hedor percibido en %s marca %s como SOSPECHOSA de Wumpus (peso A* = 25.0)." % [str(v_pos), str(n_pos)]
					)

		# Regla R5 (Aislamiento Deductivo de Pozo por Eliminacion)
		for v_pos: Vector2i in epistemic_map.visited_cells:
			var v_cell: CellBeliefData = epistemic_map.get_cell(v_pos)
			if v_cell == null or not v_cell.visited or not v_cell.breeze:
				continue

			var candidates: Array[Vector2i] = []
			for n_pos: Vector2i in epistemic_map.get_passable_orthogonal_neighbors(v_pos):
				var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
				if n_cell.pit_state != GameConstants.FactState.SAFE:
					candidates.append(n_pos)

			if candidates.size() == 1:
				var pit_pos: Vector2i = candidates[0]
				var pit_cell: CellBeliefData = epistemic_map.get_cell(pit_pos)
				if pit_cell.pit_state != GameConstants.FactState.CONFIRMED:
					pit_cell.pit_state = GameConstants.FactState.CONFIRMED
					pit_cell.overall_state = GameConstants.OverallState.CONFIRMED_HAZARD
					nav_planner.mark_cell_hazard_or_wall(pit_pos)
					deduction_made = true
					_emit_xai_once(
						turn_number,
						"R5",
						"R5_%s" % [str(pit_pos)],
						"Eliminacion deductiva desde %s confirma POZO en %s (celda bloqueada en A*)." % [str(v_pos), str(pit_pos)]
					)

		# Regla R6 (Localizacion Exacta del Wumpus y Disparo de Flecha)
		if not epistemic_map.wumpus_killed:
			for v_pos: Vector2i in epistemic_map.visited_cells:
				var v_cell: CellBeliefData = epistemic_map.get_cell(v_pos)
				if v_cell == null or not v_cell.visited or not v_cell.stench:
					continue

				var w_candidates: Array[Vector2i] = []
				for n_pos: Vector2i in epistemic_map.get_passable_orthogonal_neighbors(v_pos):
					var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
					if n_cell.wumpus_state != GameConstants.FactState.SAFE:
						w_candidates.append(n_pos)

				if w_candidates.size() == 1:
					var w_pos: Vector2i = w_candidates[0]
					var w_cell: CellBeliefData = epistemic_map.get_cell(w_pos)
					confirmed_wumpus_cell = w_pos
					if w_cell.wumpus_state != GameConstants.FactState.CONFIRMED:
						w_cell.wumpus_state = GameConstants.FactState.CONFIRMED
						deduction_made = true
						_emit_xai_once(
							turn_number,
							"R6",
							"R6_LOC_%s" % [str(w_pos)],
							"Triangulacion de hedor desde %s confirma ubicacion exacta del WUMPUS en %s." % [str(v_pos), str(w_pos)]
						)

					# Verificar si el agente tiene flecha y esta alineado ortogonalmente sin muros intermedios
					if epistemic_map.has_arrow and _has_clear_orthogonal_line_of_fire(epistemic_map, epistemic_map.agent_pos, w_pos):
						epistemic_map.has_arrow = false
						arrow_shot_performed = true
						arrow_target_cell = w_pos
						arrow_hit_success = world_truth.check_arrow_hit(epistemic_map.agent_pos, w_pos)
						if arrow_hit_success:
							epistemic_map.wumpus_killed = true
							_clear_wumpus_across_map(epistemic_map)
							deduction_made = true
							EventBus.xai_rule_triggered.emit(
								turn_number,
								"R6",
								"¡Disparo de flecha desde %s hacia %s! GRITO escuchado: Wumpus eliminado y celdas liberadas." % [str(epistemic_map.agent_pos), str(w_pos)]
							)
						else:
							EventBus.xai_rule_triggered.emit(
								turn_number,
								"R6",
								"Flecha disparada desde %s hacia %s sin impacto." % [str(epistemic_map.agent_pos), str(w_pos)]
							)
						EventBus.agent_arrow_fired.emit(epistemic_map.agent_pos, w_pos, arrow_hit_success)

		# Regla R3 (Certificacion de Celda Segura) y consolidacion de estados AStar
		for pos: Vector2i in epistemic_map.cells.keys():
			var cell: CellBeliefData = epistemic_map.get_cell(pos)
			if cell.is_wall:
				if cell.overall_state != GameConstants.OverallState.CONFIRMED_HAZARD:
					cell.overall_state = GameConstants.OverallState.CONFIRMED_HAZARD
					deduction_made = true
				nav_planner.mark_cell_hazard_or_wall(pos)
				continue

			if cell.pit_state == GameConstants.FactState.CONFIRMED or (cell.wumpus_state == GameConstants.FactState.CONFIRMED and not epistemic_map.wumpus_killed):
				if cell.overall_state != GameConstants.OverallState.CONFIRMED_HAZARD:
					cell.overall_state = GameConstants.OverallState.CONFIRMED_HAZARD
					deduction_made = true
				nav_planner.mark_cell_hazard_or_wall(pos)
				continue

			# Regla R3: SI pit_state == SAFE Y wumpus_state == SAFE Y is_wall == false -> SAFE
			if cell.pit_state == GameConstants.FactState.SAFE and cell.wumpus_state == GameConstants.FactState.SAFE:
				if cell.overall_state != GameConstants.OverallState.SAFE:
					cell.overall_state = GameConstants.OverallState.SAFE
					deduction_made = true
					if not cell.visited:
						_emit_xai_once(
							turn_number,
							"R3",
							"R3_%s" % [str(pos)],
							"Celda %s certificada 100%% SEGURA (peso A* = 1.0)." % [str(pos)]
						)
				nav_planner.mark_cell_safe(pos)
				continue

			# Consolidacion Regla R4: Si alguna es SUSPICIOUS y ninguna CONFIRMED -> SUSPICIOUS
			if cell.pit_state == GameConstants.FactState.SUSPICIOUS or cell.wumpus_state == GameConstants.FactState.SUSPICIOUS:
				if cell.overall_state != GameConstants.OverallState.SUSPICIOUS:
					cell.overall_state = GameConstants.OverallState.SUSPICIOUS
					deduction_made = true
				nav_planner.mark_cell_suspicious(pos)

	return {
		"confirmed_wumpus_cell": confirmed_wumpus_cell,
		"arrow_shot_performed": arrow_shot_performed,
		"arrow_target_cell": arrow_target_cell,
		"arrow_hit_success": arrow_hit_success
	}

func evaluate_rule_r7_gold_capture(
	epistemic_map: EpistemicMapData,
	world_truth: WorldTruthData,
	turn_number: int
) -> bool:
	var current_cell: CellBeliefData = epistemic_map.get_cell(epistemic_map.agent_pos)
	if current_cell == null:
		return false

	if current_cell.glitter and not epistemic_map.has_gold:
		epistemic_map.has_gold = true
		world_truth.gold_collected = true
		current_cell.glitter = false
		EventBus.xai_rule_triggered.emit(
			turn_number,
			"R7",
			"¡Resplandor detectado en %s! Lingote de Oro capturado. Fijando meta de extraccion en (0, 0)." % [str(epistemic_map.agent_pos)]
		)
		return true
	return false

func reconstruct_epistemic_state_r8(
	epistemic_map: EpistemicMapData,
	nav_planner: NavigationPlannerAStar,
	world_truth: WorldTruthData,
	turn_number: int,
	edit_reason: String
) -> Dictionary:
	# Regla 5 y Regla R8: Reconstruccion Epistemica Determinista ante edicion del Modo Dios
	_announced_keys.clear()

	# Si el Wumpus fue revivido o reubicado vivo por el Modo Dios, actualizamos wumpus_killed
	if world_truth.wumpus_alive and world_truth.wumpus_pos != Vector2i(-1, -1):
		epistemic_map.wumpus_killed = false

	#Si el Oro fue movido de nuevo al tablero por el Modo Dios, el agente debe ir a recogerlo
	if not world_truth.gold_collected:
		epistemic_map.has_gold = false

	# Actualizar muros conocidos y re-muestrear sensores de todas las celdas visitadas
	var valid_visited: Array[Vector2i] = []
	for v_pos: Vector2i in epistemic_map.visited_cells:
		if world_truth.has_wall(v_pos):
			var w_belief: CellBeliefData = epistemic_map.get_cell(v_pos)
			if w_belief != null:
				w_belief.visited = false
				w_belief.is_wall = true
			continue
		valid_visited.append(v_pos)

	epistemic_map.visited_cells = valid_visited

	for pos: Vector2i in epistemic_map.cells.keys():
		var c: CellBeliefData = epistemic_map.get_cell(pos)
		if c.is_wall and not world_truth.has_wall(pos):
			# Si el Modo Dios elimino un muro previamente detectado, vuelve a ser explorable
			c.is_wall = false

	for v_pos: Vector2i in epistemic_map.visited_cells:
		var percepts: Dictionary = world_truth.sample_percepts_at(v_pos)
		var belief: CellBeliefData = epistemic_map.get_cell(v_pos)
		if belief != null:
			belief.breeze = bool(percepts.get("breeze", false))
			belief.stench = false if epistemic_map.wumpus_killed else bool(percepts.get("stench", false))
			belief.glitter = bool(percepts.get("glitter", false))

	# Limpiar deducciones en celdas no visitadas a UNKNOWN y re-ejecutar Forward Chaining R1-R6
	epistemic_map.reset_non_visited_deductions()

	EventBus.xai_rule_triggered.emit(
		turn_number,
		"R8",
		"Revision Epistemica (Modo Dios: %s). Re-evaluando base de hechos desde cero." % [edit_reason]
	)

	return run_forward_chaining(epistemic_map, nav_planner, world_truth, turn_number)

func _has_clear_orthogonal_line_of_fire(epistemic_map: EpistemicMapData, from_cell: Vector2i, target_cell: Vector2i) -> bool:
	var delta: Vector2i = target_cell - from_cell
	if delta == Vector2i.ZERO:
		return false
	if delta.x != 0 and delta.y != 0:
		return false
	var step: Vector2i = Vector2i(signi(delta.x), signi(delta.y))
	var cursor: Vector2i = from_cell + step
	while epistemic_map.is_within_bounds(cursor):
		var belief: CellBeliefData = epistemic_map.get_cell(cursor)
		if belief != null and belief.is_wall:
			return false
		if cursor == target_cell:
			return true
		cursor += step
	return false

func _clear_wumpus_across_map(epistemic_map: EpistemicMapData) -> void:
	for pos: Vector2i in epistemic_map.cells.keys():
		var belief: CellBeliefData = epistemic_map.get_cell(pos)
		belief.stench = false
		belief.wumpus_state = GameConstants.FactState.SAFE
		if not belief.is_wall and belief.pit_state == GameConstants.FactState.SAFE:
			belief.overall_state = GameConstants.OverallState.SAFE
		elif not belief.is_wall and belief.pit_state == GameConstants.FactState.SUSPICIOUS:
			belief.overall_state = GameConstants.OverallState.SUSPICIOUS
		elif not belief.is_wall and belief.pit_state == GameConstants.FactState.UNKNOWN:
			belief.overall_state = GameConstants.OverallState.UNKNOWN
