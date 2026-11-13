class_name KnowledgeEngine
extends RefCounted
## Motor de IA: KnowledgeEngine
## Orquestador del Sistema Hibrido (Base de Hechos Epistemica + Motor de Reglas RBR +
## Planificador AStarGrid2D + Razonador Basado en Casos 4R).

var epistemic_map: EpistemicMapData
var nav_planner: NavigationPlannerAStar
var rule_engine: RuleEngineRBR
var cbr_engine: CaseBasedReasoner4R

var active_path: Array[Vector2i] = []
var current_goal_cell: Vector2i = Vector2i.ZERO
var last_step_used_cbr: bool = false

func _init(initial_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE) -> void:
	epistemic_map = EpistemicMapData.new(initial_size)
	nav_planner = NavigationPlannerAStar.new(initial_size)
	rule_engine = RuleEngineRBR.new()
	cbr_engine = CaseBasedReasoner4R.new()

func reset_knowledge(new_size: Vector2i) -> void:
	epistemic_map.initialize_grid(new_size)
	nav_planner.initialize_grid(new_size)
	rule_engine.clear_announced_history()
	active_path.clear()
	current_goal_cell = Vector2i.ZERO
	last_step_used_cbr = false

func perceive_and_reason_at_current_cell(world_truth: WorldTruthData, turn_number: int) -> Dictionary:
	var pos: Vector2i = epistemic_map.agent_pos
	var percepts: Dictionary = world_truth.sample_percepts_at(pos)
	epistemic_map.register_visited_percepts(pos, percepts)

	# Si el paso anterior fue producto de una decision de riesgo RBC (4R), ejecutamos REVISE/RETAIN
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

	# Regla R7: Verificar captura del Lingote de Oro
	var gold_just_captured: bool = rule_engine.evaluate_rule_r7_gold_capture(epistemic_map, world_truth, turn_number)
	if gold_just_captured:
		active_path.clear()

	# Ejecutar inferencia Forward Chaining (Reglas R1 a R6)
	var rbr_result: Dictionary = rule_engine.run_forward_chaining(epistemic_map, nav_planner, world_truth, turn_number)

	return {
		"survived": true,
		"gold_just_captured": gold_just_captured,
		"arrow_shot_performed": bool(rbr_result.get("arrow_shot_performed", false)),
		"confirmed_wumpus_cell": rbr_result.get("confirmed_wumpus_cell", Vector2i(-1, -1)) as Vector2i
	}

func handle_god_mode_modification(world_truth: WorldTruthData, turn_number: int, edit_reason: String) -> void:
	rule_engine.reconstruct_epistemic_state_r8(epistemic_map, nav_planner, world_truth, turn_number, edit_reason)
	active_path.clear()
	plan_next_route(turn_number)

func plan_next_route(turn_number: int) -> Dictionary:
	# 1. Si el agente ya tiene el oro, su objetivo global es regresar a (0, 0) (Regla R7)
	if epistemic_map.has_gold:
		if epistemic_map.agent_pos == Vector2i.ZERO:
			active_path.clear()
			return {"status": "AT_EXTRACTION_WITH_GOLD", "next_cell": Vector2i.ZERO}

		var return_path: Array[Vector2i] = nav_planner.compute_grid_path(epistemic_map.agent_pos, Vector2i.ZERO)
		if not return_path.is_empty() and return_path.size() >= 2:
			active_path = return_path
			current_goal_cell = Vector2i.ZERO
			return {"status": "HAS_ROUTE", "next_cell": active_path[1]}
		else:
			active_path.clear()
			return {"status": "BLOCKED", "reason": "Ruta de extraccion hacia (0, 0) bloqueada por muros o peligros."}

	# 2. Si el Wumpus esta confirmado y vivo y el agente aun tiene su flecha, buscar alineacion ortogonal segura para disparar
	if epistemic_map.has_arrow and not epistemic_map.wumpus_killed:
		var confirmed_w: Vector2i = _find_confirmed_wumpus_cell()
		if confirmed_w != Vector2i(-1, -1):
			var vantage_path: Array[Vector2i] = _find_best_safe_vantage_path_for_wumpus(confirmed_w)
			if not vantage_path.is_empty() and vantage_path.size() >= 2:
				active_path = vantage_path
				current_goal_cell = vantage_path[vantage_path.size() - 1]
				return {"status": "HAS_ROUTE", "next_cell": active_path[1]}

	# 3. Buscar celdas frontera no visitadas con estado SAFE (Peso 1.0)
	var safe_frontiers: Array[Vector2i] = []
	var suspicious_frontiers: Array[Vector2i] = []

	for pos: Vector2i in epistemic_map.cells.keys():
		var belief: CellBeliefData = epistemic_map.get_cell(pos)
		if belief.visited or belief.is_wall:
			continue
		if belief.overall_state == GameConstants.OverallState.SAFE:
			safe_frontiers.append(pos)
		elif belief.overall_state == GameConstants.OverallState.SUSPICIOUS:
			suspicious_frontiers.append(pos)

	var best_safe_path: Array[Vector2i] = _find_lowest_cost_path_to_candidates(safe_frontiers, true)
	if not best_safe_path.is_empty() and best_safe_path.size() >= 2:
		active_path = best_safe_path
		current_goal_cell = best_safe_path[best_safe_path.size() - 1]
		last_step_used_cbr = false
		return {"status": "HAS_ROUTE", "next_cell": active_path[1]}

	# 4. Si no existen fronteras SAFE alcanzables, invocar el Razonador Basado en Casos 4R (Seccion 3.3)
	var cbr_decision: Dictionary = cbr_engine.select_risky_frontier_cell(
		epistemic_map,
		nav_planner,
		suspicious_frontiers,
		turn_number
	)
	if bool(cbr_decision.get("has_target", false)):
		var cbr_path: Array[Vector2i] = cbr_decision.get("path", [])
		if cbr_path.size() >= 2:
			active_path = cbr_path
			current_goal_cell = cbr_decision.get("target_cell", Vector2i.ZERO) as Vector2i
			if active_path.size() == 2:
				last_step_used_cbr = true
			return {"status": "HAS_ROUTE", "next_cell": active_path[1]}

	# 5. Estado de Bloqueo Seguro (WAITING_FOR_GOD_MODE - Seccion 3.4)
	active_path.clear()
	return {
		"status": "BLOCKED",
		"reason": "Sin fronteras alcanzables. Todas las rutas estan bloqueadas por muros o amenazas confirmadas."
	}

func _find_lowest_cost_path_to_candidates(candidates: Array[Vector2i], require_pure_safe_steps: bool) -> Array[Vector2i]:
	var best_path: Array[Vector2i] = []
	var best_cost: float = INF

	for target: Vector2i in candidates:
		var path: Array[Vector2i] = nav_planner.compute_grid_path(epistemic_map.agent_pos, target)
		if path.is_empty() or path.size() < 2:
			continue

		if require_pure_safe_steps:
			var crosses_suspicious: bool = false
			for i: int in range(1, path.size()):
				var step_belief: CellBeliefData = epistemic_map.get_cell(path[i])
				if step_belief == null or step_belief.overall_state != GameConstants.OverallState.SAFE:
					crosses_suspicious = true
					break
			if crosses_suspicious:
				continue

		var cost: float = nav_planner.compute_path_cost(path)
		if cost < best_cost:
			best_cost = cost
			best_path = path

	return best_path

func _find_confirmed_wumpus_cell() -> Vector2i:
	for pos: Vector2i in epistemic_map.cells.keys():
		var belief: CellBeliefData = epistemic_map.get_cell(pos)
		if belief.wumpus_state == GameConstants.FactState.CONFIRMED and not epistemic_map.wumpus_killed:
			return pos
	return Vector2i(-1, -1)

func _find_best_safe_vantage_path_for_wumpus(wumpus_cell: Vector2i) -> Array[Vector2i]:
	var vantage_candidates: Array[Vector2i] = []
	for dir: Vector2i in GameConstants.ORTHOGONAL_DIRS:
		var cursor: Vector2i = wumpus_cell + dir
		while epistemic_map.is_within_bounds(cursor):
			var belief: CellBeliefData = epistemic_map.get_cell(cursor)
			if belief == null or belief.is_wall:
				break
			if belief.overall_state == GameConstants.OverallState.SAFE:
				vantage_candidates.append(cursor)
			cursor += dir
	return _find_lowest_cost_path_to_candidates(vantage_candidates, true)

func emit_epistemic_visual_update() -> void:
	var visual_snapshot: Dictionary = epistemic_map.build_visual_states_snapshot()
	EventBus.epistemic_state_updated.emit(visual_snapshot, active_path.duplicate())
