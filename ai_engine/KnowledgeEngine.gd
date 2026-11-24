class_name KnowledgeEngine
extends RefCounted
## Motor de IA: KnowledgeEngine
## Orquestador Hibrido multipiso (hasta 5 pisos) con prioridad estricta de
## supervivencia:
##   1. Si tiene el Oro -> retorno estrictamente seguro a (0, 0, P1).
##   2. Explora TODAS las celdas frontera 100% SAFE alcanzables mediante rodeos
##      estrictamente seguros (A* safe-only) para recopilar pistas de Buscaminas
##      y evitar entrar en pasillos peligrosos sin antes rodearlos.
##   3. Si tiene flechas y un Wumpus confirmado (o sospechoso con pozo seguro),
##      se posiciona de forma segura para abatirlo antes de arriesgarse.
##   4. Solo si no queda ninguna celda SAFE ni disparo util, invoca RBC-4R con
##      probabilidad minima CSP.

var epistemic_map: EpistemicMapData
var nav_planner: NavigationPlannerAStar
var rule_engine: RuleEngineRBR
var cbr_engine: CaseBasedReasoner4R

var active_path: Array[Vector3i] = []
var current_goal_cell: Vector3i = Vector3i.ZERO
var last_step_used_cbr: bool = false

func _init(initial_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE, initial_floors: int = 1) -> void:
	epistemic_map = EpistemicMapData.new(initial_size, initial_floors)
	nav_planner = NavigationPlannerAStar.new(initial_size, initial_floors)
	rule_engine = RuleEngineRBR.new()
	cbr_engine = CaseBasedReasoner4R.new()

func reset_knowledge(new_size: Vector2i, new_floor_count: int = 1) -> void:
	epistemic_map.initialize_grid(new_size, new_floor_count)
	nav_planner.initialize_grid(new_size, new_floor_count)
	rule_engine.clear_announced_history()
	active_path.clear()
	current_goal_cell = Vector3i.ZERO
	last_step_used_cbr = false
	EventBus.agent_inventory_updated.emit(epistemic_map.arrow_count, epistemic_map.has_gold)

func perceive_and_reason_at_current_cell(world_truth: WorldTruthData, turn_number: int) -> Dictionary:
	var pos: Vector3i = epistemic_map.agent_pos
	var percepts: Dictionary = world_truth.sample_percepts_at(pos)
	epistemic_map.register_visited_percepts(pos, percepts)

	var survived: bool = (not bool(percepts.get("has_pit", false))) and (not bool(percepts.get("has_live_wumpus", false)))
	if last_step_used_cbr:
		cbr_engine.revise_and_retain_episode(survived, pos, turn_number)
		last_step_used_cbr = false

	if not survived:
		return {
			"survived": false,
			"killed_by_pit": bool(percepts.get("has_pit", false)),
			"killed_by_wumpus": bool(percepts.get("has_live_wumpus", false))
		}

	var pickup_res: Dictionary = rule_engine.evaluate_rule_r7_gold_and_arrows(epistemic_map, world_truth, turn_number)
	var gold_just_captured: bool = bool(pickup_res.get("gold_captured", false))
	var arrow_picked: bool = bool(pickup_res.get("arrow_picked", false))
	if gold_just_captured:
		active_path.clear()

	var rbr_result: Dictionary = rule_engine.run_forward_chaining(epistemic_map, nav_planner, world_truth, turn_number)

	return {
		"survived": true,
		"gold_just_captured": gold_just_captured,
		"arrow_picked": arrow_picked,
		"arrow_shot_performed": bool(rbr_result.get("arrow_shot_performed", false))
	}

func handle_god_mode_modification(world_truth: WorldTruthData, turn_number: int, edit_reason: String) -> void:
	rule_engine.reconstruct_epistemic_state_r8(epistemic_map, nav_planner, world_truth, turn_number, edit_reason)
	active_path.clear()
	plan_next_route(turn_number, world_truth)

func plan_next_route(turn_number: int, world_truth: WorldTruthData = null) -> Dictionary:
	# 1. Si ya tiene el Oro -> volver de forma ESTRICTAMENTE SEGURA a (0, 0, P1)
	if epistemic_map.has_gold:
		if epistemic_map.agent_pos == Vector3i(0, 0, 0):
			active_path.clear()
			return {"status": "AT_EXTRACTION_WITH_GOLD", "next_cell": Vector3i(0, 0, 0)}

		var safe_return: Array[Vector3i] = nav_planner.compute_grid_path_3d(
			epistemic_map.agent_pos,
			Vector3i(0, 0, 0),
			epistemic_map.known_special_links,
			true
		)
		if safe_return.size() >= 2:
			active_path = safe_return
			current_goal_cell = Vector3i(0, 0, 0)
			return {"status": "HAS_ROUTE", "next_cell": active_path[1]}

		active_path.clear()
		return {"status": "BLOCKED", "reason": "Ruta segura de extraccion hacia (0,0,P1) bloqueada."}

	# 2. PRIORIDAD MAXIMA DE EXPLORACION: Buscar TODA frontera 100% SAFE alcanzable
	#    con A* strict_safe_only = true (siempre rodea pasillos con pozos para deducir como Buscaminas!)
	var safe_frontiers: Array[Vector3i] = []
	var suspicious_frontiers: Array[Vector3i] = []

	for pos: Vector3i in epistemic_map.cells.keys():
		var belief: CellBeliefData = epistemic_map.get_cell(pos)
		if belief.visited or belief.is_wall:
			continue
		if belief.overall_state == GameConstants.OverallState.SAFE:
			safe_frontiers.append(pos)
		elif belief.overall_state == GameConstants.OverallState.SUSPICIOUS:
			suspicious_frontiers.append(pos)

	var best_safe_path: Array[Vector3i] = _find_lowest_cost_safe_path(safe_frontiers)
	if best_safe_path.size() >= 2:
		active_path = best_safe_path
		current_goal_cell = best_safe_path[best_safe_path.size() - 1]
		last_step_used_cbr = false
		return {"status": "HAS_ROUTE", "next_cell": active_path[1]}

	# 3. Si no quedan fronteras SAFE, pero tenemos flechas y un Wumpus confirmado -> ir a linea de tiro segura
	if epistemic_map.arrow_count > 0:
		var confirmed_w_list: Array[Vector3i] = _find_confirmed_wumpus_cells()
		for cw: Vector3i in confirmed_w_list:
			var vantage_path: Array[Vector3i] = _find_best_safe_vantage_path_for_target(cw)
			if vantage_path.size() >= 2:
				active_path = vantage_path
				current_goal_cell = vantage_path[vantage_path.size() - 1]
				return {"status": "HAS_ROUTE", "next_cell": active_path[1]}

		# 3b. Si no hay Wumpus confirmado pero hay sospechoso de Wumpus (sin pozo) y tenemos flechas,
		#     disparar preventivamente desde una posicion alineada antes de suicidarse caminando!
		if world_truth != null:
			var prob_w_target: Vector3i = _find_highest_prob_wumpus_suspect()
			if prob_w_target.x >= 0:
				if rule_engine._has_clear_orthogonal_line_of_fire(epistemic_map, epistemic_map.agent_pos, prob_w_target):
					rule_engine.fire_arrow_at(epistemic_map, world_truth, prob_w_target, turn_number)
					rule_engine.run_forward_chaining(epistemic_map, nav_planner, world_truth, turn_number)
					EventBus.world_truth_changed.emit(world_truth.to_snapshot())
					return plan_next_route(turn_number, null)
				else:
					var probe_vantage: Array[Vector3i] = _find_best_safe_vantage_path_for_target(prob_w_target)
					if probe_vantage.size() >= 2:
						active_path = probe_vantage
						current_goal_cell = probe_vantage[probe_vantage.size() - 1]
						return {"status": "HAS_ROUTE", "next_cell": active_path[1]}

	# 4. Solo cuando NO hay ninguna celda 100% SAFE ni tiro tactico disponible -> RBC 4R + CSP Minimo Riesgo
	var cbr_decision: Dictionary = cbr_engine.select_risky_frontier_cell(
		epistemic_map,
		nav_planner,
		suspicious_frontiers,
		turn_number
	)
	if bool(cbr_decision.get("has_target", false)):
		var cbr_path: Array[Vector3i] = cbr_decision.get("path", [])
		if cbr_path.size() >= 2:
			active_path = cbr_path
			current_goal_cell = cbr_decision.get("target_cell", Vector3i.ZERO) as Vector3i
			if active_path.size() == 2:
				last_step_used_cbr = true
			return {"status": "HAS_ROUTE", "next_cell": active_path[1]}

	# 5. Estado de Bloqueo Seguro (WAITING_FOR_GOD_MODE)
	active_path.clear()
	return {
		"status": "BLOCKED",
		"reason": "Sin fronteras alcanzables. Rutas bloqueadas por muros o peligros confirmados."
	}

func _find_lowest_cost_safe_path(candidates: Array[Vector3i]) -> Array[Vector3i]:
	var best_path: Array[Vector3i] = []
	var best_cost: float = INF

	for target: Vector3i in candidates:
		# strict_safe_only = true garantiza rodeos 100% seguros sin atajos suicidas!
		var path: Array[Vector3i] = nav_planner.compute_grid_path_3d(
			epistemic_map.agent_pos,
			target,
			epistemic_map.known_special_links,
			true
		)
		if path.size() < 2:
			continue

		var cost: float = nav_planner.compute_path_cost_3d(path, true)
		if cost < best_cost:
			best_cost = cost
			best_path = path

	return best_path

func _find_confirmed_wumpus_cells() -> Array[Vector3i]:
	var res: Array[Vector3i] = []
	for pos: Vector3i in epistemic_map.cells.keys():
		var belief: CellBeliefData = epistemic_map.get_cell(pos)
		if belief.wumpus_state == GameConstants.FactState.CONFIRMED:
			res.append(pos)
	return res

func _find_highest_prob_wumpus_suspect() -> Vector3i:
	var best_pos: Vector3i = Vector3i(-1, -1, -1)
	var best_p: float = 0.0
	for pos: Vector3i in epistemic_map.cells.keys():
		var b: CellBeliefData = epistemic_map.get_cell(pos)
		if b.visited or b.is_wall:
			continue
		if b.wumpus_state == GameConstants.FactState.SUSPICIOUS and b.pit_state == GameConstants.FactState.SAFE:
			var p: float = b.wumpus_probability if b.wumpus_probability > 0.0 else 0.35
			if p > best_p:
				best_p = p
				best_pos = pos
	return best_pos

func _find_best_safe_vantage_path_for_target(target_cell: Vector3i) -> Array[Vector3i]:
	var vantage_candidates: Array[Vector3i] = []
	for dir: Vector2i in GameConstants.ORTHOGONAL_DIRS:
		var cursor: Vector3i = Vector3i(target_cell.x + dir.x, target_cell.y + dir.y, target_cell.z)
		while epistemic_map.is_within_bounds(cursor):
			var belief: CellBeliefData = epistemic_map.get_cell(cursor)
			if belief == null or belief.is_wall:
				break
			if belief.overall_state == GameConstants.OverallState.SAFE:
				vantage_candidates.append(cursor)
			cursor = Vector3i(cursor.x + dir.x, cursor.y + dir.y, cursor.z)
	return _find_lowest_cost_safe_path(vantage_candidates)

func emit_epistemic_visual_update() -> void:
	var visual_3d: Dictionary = epistemic_map.build_visual_states_snapshot_3d()
	EventBus.epistemic_multifloor_updated.emit(visual_3d, active_path.duplicate())

	var visual_2d: Dictionary = epistemic_map.build_visual_states_snapshot_floor(GameConstants.active_view_floor)
	var path_2d: Array[Vector2i] = []
	for step_c: Vector3i in active_path:
		if step_c.z == GameConstants.active_view_floor:
			path_2d.append(Vector2i(step_c.x, step_c.y))
	EventBus.epistemic_state_updated.emit(visual_2d, path_2d)
