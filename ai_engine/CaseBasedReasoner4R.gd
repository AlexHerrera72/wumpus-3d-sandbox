class_name CaseBasedReasoner4R
extends RefCounted
## Motor de IA: CaseBasedReasoner4R
## Planificador de Segundo Principio basado en Razonamiento Basado en Casos (Ciclo 4R)
## combinado con las probabilidades exactas CSP del solucionador estilo Buscaminas
## para elegir SIEMPRE la casilla con menor probabilidad matematica de peligro
## cuando ya no queda ninguna ruta 100% segura alcanzable.

enum PatternToken {
	OUT_OF_BOUNDS_OR_WALL = 0,
	VISITED_CALM = 1,
	VISITED_BREEZE = 2,
	VISITED_STENCH = 3,
	VISITED_BOTH = 4,
	FRONTIER_SAFE = 5,
	FRONTIER_SUSPICIOUS_PIT = 6,
	FRONTIER_SUSPICIOUS_WUMPUS = 7,
	FRONTIER_SUSPICIOUS_BOTH = 8,
	CONFIRMED_HAZARD = 9,
	UNKNOWN_CELL = 10
}

const SIMILARITY_THRESHOLD: float = 0.60
const RETAIN_SIMILARITY_CEILING: float = 0.85

const WINDOW_WEIGHTS: Array[float] = [
	0.75, 1.50, 0.75,
	1.50, 2.00, 1.50,
	0.75, 1.50, 0.75
]

const WINDOW_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),  Vector2i(0, 0),  Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1)
]

var case_memory: Array[Dictionary] = []
var _has_active_episode: bool = false
var _active_episode_pattern: Array[int] = []
var _active_episode_dir: Vector2i = Vector2i.ZERO
var _active_episode_similarity: float = 0.0
var _active_episode_matched_index: int = -1

func _init() -> void:
	_load_seed_cases()

func _load_seed_cases() -> void:
	case_memory.clear()
	case_memory.append({
		"pattern": [
			PatternToken.OUT_OF_BOUNDS_OR_WALL, PatternToken.FRONTIER_SUSPICIOUS_PIT, PatternToken.UNKNOWN_CELL,
			PatternToken.VISITED_CALM,          PatternToken.VISITED_BREEZE,          PatternToken.FRONTIER_SUSPICIOUS_PIT,
			PatternToken.VISITED_CALM,          PatternToken.VISITED_BREEZE,          PatternToken.CONFIRMED_HAZARD
		],
		"chosen_dir": Vector2i(0, -1),
		"outcome": "SUCCESS"
	})
	case_memory.append({
		"pattern": [
			PatternToken.OUT_OF_BOUNDS_OR_WALL, PatternToken.VISITED_CALM,            PatternToken.FRONTIER_SUSPICIOUS_PIT,
			PatternToken.OUT_OF_BOUNDS_OR_WALL, PatternToken.VISITED_BREEZE,          PatternToken.FRONTIER_SUSPICIOUS_PIT,
			PatternToken.OUT_OF_BOUNDS_OR_WALL, PatternToken.FRONTIER_SUSPICIOUS_PIT, PatternToken.UNKNOWN_CELL
		],
		"chosen_dir": Vector2i(1, 0),
		"outcome": "SUCCESS"
	})
	case_memory.append({
		"pattern": [
			PatternToken.VISITED_CALM,   PatternToken.VISITED_CALM,               PatternToken.OUT_OF_BOUNDS_OR_WALL,
			PatternToken.VISITED_CALM,   PatternToken.VISITED_STENCH,             PatternToken.FRONTIER_SUSPICIOUS_WUMPUS,
			PatternToken.UNKNOWN_CELL,   PatternToken.FRONTIER_SUSPICIOUS_WUMPUS, PatternToken.UNKNOWN_CELL
		],
		"chosen_dir": Vector2i(0, 1),
		"outcome": "SUCCESS"
	})
	case_memory.append({
		"pattern": [
			PatternToken.VISITED_BREEZE, PatternToken.CONFIRMED_HAZARD,        PatternToken.UNKNOWN_CELL,
			PatternToken.VISITED_CALM,   PatternToken.VISITED_BREEZE,          PatternToken.FRONTIER_SUSPICIOUS_PIT,
			PatternToken.VISITED_CALM,   PatternToken.FRONTIER_SUSPICIOUS_PIT, PatternToken.UNKNOWN_CELL
		],
		"chosen_dir": Vector2i(1, 0),
		"outcome": "SUCCESS"
	})

func extract_3x3_pattern(epistemic_map: EpistemicMapData, center_cell: Vector3i) -> Array[int]:
	var pattern: Array[int] = []
	for offset: Vector2i in WINDOW_OFFSETS:
		var target: Vector3i = Vector3i(center_cell.x + offset.x, center_cell.y + offset.y, center_cell.z)
		if not epistemic_map.is_within_bounds(target):
			pattern.append(PatternToken.OUT_OF_BOUNDS_OR_WALL)
			continue
		var belief: CellBeliefData = epistemic_map.get_cell(target)
		if belief == null or belief.is_wall:
			pattern.append(PatternToken.OUT_OF_BOUNDS_OR_WALL)
			continue
		if belief.overall_state == GameConstants.OverallState.CONFIRMED_HAZARD:
			pattern.append(PatternToken.CONFIRMED_HAZARD)
			continue
		if belief.visited:
			if belief.breeze and belief.stench:
				pattern.append(PatternToken.VISITED_BOTH)
			elif belief.breeze:
				pattern.append(PatternToken.VISITED_BREEZE)
			elif belief.stench:
				pattern.append(PatternToken.VISITED_STENCH)
			else:
				pattern.append(PatternToken.VISITED_CALM)
			continue
		if belief.overall_state == GameConstants.OverallState.SAFE:
			pattern.append(PatternToken.FRONTIER_SAFE)
		elif belief.overall_state == GameConstants.OverallState.SUSPICIOUS:
			var sp_pit: bool = belief.pit_state == GameConstants.FactState.SUSPICIOUS
			var sp_wump: bool = belief.wumpus_state == GameConstants.FactState.SUSPICIOUS
			if sp_pit and sp_wump:
				pattern.append(PatternToken.FRONTIER_SUSPICIOUS_BOTH)
			elif sp_pit:
				pattern.append(PatternToken.FRONTIER_SUSPICIOUS_PIT)
			else:
				pattern.append(PatternToken.FRONTIER_SUSPICIOUS_WUMPUS)
		else:
			pattern.append(PatternToken.UNKNOWN_CELL)
	return pattern

func _delta_feature_similarity(token_a: int, token_b: int) -> float:
	if token_a == token_b:
		return 1.0
	var suspicious_group: Array[int] = [
		PatternToken.FRONTIER_SUSPICIOUS_PIT,
		PatternToken.FRONTIER_SUSPICIOUS_WUMPUS,
		PatternToken.FRONTIER_SUSPICIOUS_BOTH
	]
	if suspicious_group.has(token_a) and suspicious_group.has(token_b):
		return 0.5
	var visited_warn_group: Array[int] = [
		PatternToken.VISITED_BREEZE,
		PatternToken.VISITED_STENCH,
		PatternToken.VISITED_BOTH
	]
	if visited_warn_group.has(token_a) and visited_warn_group.has(token_b):
		return 0.5
	return 0.0

func compute_weighted_similarity(pattern_actual: Array[int], pattern_case: Array) -> float:
	if pattern_actual.size() != 9 or pattern_case.size() != 9:
		return 0.0
	var weighted_sum: float = 0.0
	var total_weight: float = 0.0
	for i: int in range(9):
		var w: float = WINDOW_WEIGHTS[i]
		var delta_val: float = _delta_feature_similarity(pattern_actual[i], int(pattern_case[i]))
		weighted_sum += w * delta_val
		total_weight += w
	if total_weight <= 0.0:
		return 0.0
	return weighted_sum / total_weight

func _get_cell_death_probability(epistemic_map: EpistemicMapData, cell: Vector3i) -> float:
	var b: CellBeliefData = epistemic_map.get_cell(cell)
	if b == null:
		return 1.0
	var p_pit: float = b.pit_probability
	if b.pit_state == GameConstants.FactState.CONFIRMED:
		p_pit = 1.0
	elif b.pit_state == GameConstants.FactState.SAFE:
		p_pit = 0.0
	elif p_pit <= 0.0 and b.pit_state == GameConstants.FactState.SUSPICIOUS:
		p_pit = 0.35

	var p_wump: float = b.wumpus_probability
	if b.wumpus_state == GameConstants.FactState.CONFIRMED:
		p_wump = 1.0
	elif b.wumpus_state == GameConstants.FactState.SAFE:
		p_wump = 0.0
	elif p_wump <= 0.0 and b.wumpus_state == GameConstants.FactState.SUSPICIOUS:
		p_wump = 0.35

	return 1.0 - (1.0 - p_pit) * (1.0 - p_wump)

func select_risky_frontier_cell(
	epistemic_map: EpistemicMapData,
	nav_planner: NavigationPlannerAStar,
	suspicious_frontiers: Array[Vector3i],
	turn_number: int
) -> Dictionary:
	if suspicious_frontiers.is_empty():
		return {"has_target": false, "target_cell": Vector3i(-1, -1, -1), "path": [] as Array[Vector3i]}

	# Encontrar la probabilidad minima de muerte disponible entre todas las fronteras sospechosas alcanzables
	var min_death_prob: float = 1.0
	var reachable_candidates: Array[Dictionary] = []
	for cand: Vector3i in suspicious_frontiers:
		var cand_path: Array[Vector3i] = nav_planner.compute_grid_path_3d(
			epistemic_map.agent_pos,
			cand,
			epistemic_map.known_special_links,
			false
		)
		if cand_path.size() < 2:
			continue
		# Asegurar que los pasos intermedios de cand_path sean SAFE (solo el destino es riesgoso!)
		var intermediate_risky: bool = false
		for i: int in range(1, cand_path.size() - 1):
			var mid_b: CellBeliefData = epistemic_map.get_cell(cand_path[i])
			if mid_b == null or mid_b.overall_state != GameConstants.OverallState.SAFE:
				intermediate_risky = true
				break
		if intermediate_risky:
			continue
		var dp: float = _get_cell_death_probability(epistemic_map, cand)
		if dp < min_death_prob:
			min_death_prob = dp
		reachable_candidates.append({"cell": cand, "path": cand_path, "prob": dp})

	if reachable_candidates.is_empty():
		return {"has_target": false, "target_cell": Vector3i(-1, -1, -1), "path": [] as Array[Vector3i]}

	var current_pattern: Array[int] = extract_3x3_pattern(epistemic_map, epistemic_map.agent_pos)

	# 1. RETRIEVE: Buscar caso exitoso similar que ademas respete el umbral de riesgo minimo CSP
	var best_sim: float = -1.0
	var best_case_idx: int = -1
	var best_dir: Vector2i = Vector2i.ZERO

	for idx: int in range(case_memory.size()):
		var c_entry: Dictionary = case_memory[idx]
		if String(c_entry.get("outcome", "")) != "SUCCESS":
			continue
		var c_pattern: Array = c_entry.get("pattern", [])
		var sim: float = compute_weighted_similarity(current_pattern, c_pattern)
		var dir2: Vector2i = c_entry.get("chosen_dir", Vector2i.ZERO) as Vector2i
		var candidate_cell: Vector3i = Vector3i(epistemic_map.agent_pos.x + dir2.x, epistemic_map.agent_pos.y + dir2.y, epistemic_map.agent_pos.z)
		var cand_prob: float = _get_cell_death_probability(epistemic_map, candidate_cell)
		# Solo aceptar el caso CBR si su probabilidad de muerte esta cerca del minimo matematico (+0.08)
		if suspicious_frontiers.has(candidate_cell) and cand_prob <= min_death_prob + 0.08 and sim > best_sim:
			best_sim = sim
			best_case_idx = idx
			best_dir = dir2

	if best_sim >= SIMILARITY_THRESHOLD and best_case_idx != -1:
		var chosen_cell: Vector3i = Vector3i(epistemic_map.agent_pos.x + best_dir.x, epistemic_map.agent_pos.y + best_dir.y, epistemic_map.agent_pos.z)
		var path_to_chosen: Array[Vector3i] = nav_planner.compute_grid_path_3d(
			epistemic_map.agent_pos,
			chosen_cell,
			epistemic_map.known_special_links,
			false
		)
		if path_to_chosen.size() >= 2:
			_start_episode(current_pattern, best_dir, best_sim, best_case_idx)
			var pct: int = int(round(_get_cell_death_probability(epistemic_map, chosen_cell) * 100.0))
			var msg: String = "RBC-4R [Caso #%d, Sim=%.2f]: Riesgo minimo (%d%%) hacia (%d,%d,P%d)." % [
				best_case_idx + 1, best_sim, pct, chosen_cell.x, chosen_cell.y, chosen_cell.z + 1
			]
			EventBus.xai_cbr_triggered.emit(turn_number, best_sim, Vector2i(chosen_cell.x, chosen_cell.y), msg)
			return {
				"has_target": true,
				"target_cell": chosen_cell,
				"path": path_to_chosen,
				"similarity": best_sim
			}

	# 2. REUSE-CSP: Elegir la frontera con menor probabilidad matematica de peligro + menor distancia
	var best_entry: Dictionary = reachable_candidates[0]
	var best_score: float = INF
	var max_any_sim: float = 0.0
	for idx: int in range(case_memory.size()):
		var s: float = compute_weighted_similarity(current_pattern, case_memory[idx].get("pattern", []))
		if s > max_any_sim:
			max_any_sim = s

	for entry: Dictionary in reachable_candidates:
		var cand: Vector3i = entry["cell"] as Vector3i
		var cand_path: Array[Vector3i] = entry["path"] as Array[Vector3i]
		var prob: float = float(entry["prob"])
		var c_belief: CellBeliefData = epistemic_map.get_cell(cand)
		var is_fully_explained: bool = false
		if c_belief != null:
			var pit_exp: bool = (c_belief.pit_state != GameConstants.FactState.SUSPICIOUS) or c_belief.pit_explained_by_confirmed
			var wump_exp: bool = (c_belief.wumpus_state != GameConstants.FactState.SUSPICIOUS) or c_belief.wumpus_explained_by_confirmed
			is_fully_explained = pit_exp and wump_exp
		var unexplained_penalty: float = 0.0 if is_fully_explained else 280.0
		var warn_neighbors: int = _count_warning_visited_neighbors(epistemic_map, cand)
		var score: float = prob * 1000.0 + unexplained_penalty + float(warn_neighbors) * 15.0 + float(cand_path.size())
		if score < best_score:
			best_score = score
			best_entry = entry

	var chosen: Vector3i = best_entry["cell"] as Vector3i
	var chosen_path: Array[Vector3i] = best_entry["path"] as Array[Vector3i]
	var chosen_prob: float = float(best_entry["prob"])
	var prev_cell: Vector3i = chosen_path[chosen_path.size() - 2]
	var eval_pattern: Array[int] = extract_3x3_pattern(epistemic_map, prev_cell)
	var final_dir: Vector2i = Vector2i(chosen.x - prev_cell.x, chosen.y - prev_cell.y)
	_start_episode(eval_pattern, final_dir, max_any_sim, -1)

	var reason: String = "Sin casillas 100%% seguras. Riesgo minimo CSP (%d%%) hacia (%d,%d,P%d)." % [
		int(round(chosen_prob * 100.0)), chosen.x, chosen.y, chosen.z + 1
	]
	EventBus.xai_cbr_triggered.emit(turn_number, max_any_sim, Vector2i(chosen.x, chosen.y), reason)
	return {
		"has_target": true,
		"target_cell": chosen,
		"path": chosen_path,
		"similarity": max_any_sim
	}

func _count_warning_visited_neighbors(epistemic_map: EpistemicMapData, cell: Vector3i) -> int:
	var count: int = 0
	for n_pos: Vector3i in epistemic_map.get_orthogonal_neighbors(cell):
		var n_belief: CellBeliefData = epistemic_map.get_cell(n_pos)
		if n_belief != null and n_belief.visited and (n_belief.breeze or n_belief.stench):
			count += 1
	return count

func _start_episode(pattern: Array[int], chosen_dir: Vector2i, similarity: float, matched_idx: int) -> void:
	_has_active_episode = true
	_active_episode_pattern = pattern.duplicate()
	_active_episode_dir = chosen_dir
	_active_episode_similarity = similarity
	_active_episode_matched_index = matched_idx

func revise_and_retain_episode(survived: bool, stepped_cell: Vector3i, turn_number: int) -> void:
	if not _has_active_episode:
		return

	var outcome_str: String = "SUCCESS" if survived else "FAILURE"
	var previous_failed: bool = false

	if _active_episode_matched_index >= 0 and _active_episode_matched_index < case_memory.size():
		if not survived:
			case_memory[_active_episode_matched_index]["outcome"] = "FAILURE"
			previous_failed = true

	if _active_episode_similarity < RETAIN_SIMILARITY_CEILING or previous_failed or not survived:
		case_memory.append({
			"pattern": _active_episode_pattern.duplicate(),
			"chosen_dir": _active_episode_dir,
			"outcome": outcome_str
		})
		var retain_msg: String = "RBC-4R [RETAIN]: Episodio (%d,%d,P%d) = %s (Casos: %d)." % [
			stepped_cell.x, stepped_cell.y, stepped_cell.z + 1, outcome_str, case_memory.size()
		]
		EventBus.xai_cbr_triggered.emit(turn_number, _active_episode_similarity, Vector2i(stepped_cell.x, stepped_cell.y), retain_msg)

	_has_active_episode = false
