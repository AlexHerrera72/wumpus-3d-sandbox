class_name CaseBasedReasoner4R
extends RefCounted
## Motor de IA: CaseBasedReasoner4R
## Planificador de Segundo Principio basado en Razonamiento Basado en Casos (Ciclo 4R:
## Retrieve, Reuse, Revise, Retain) para toma de decisiones bajo incertidumbre cuando
## no existen celdas frontera 100% seguras.

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

# Pesos de la ventana 3x3 (centro = indice 4, vecinos ortogonales = 1, 3, 5, 7 con mayor peso)
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
	# Caso semilla 1: Agente en celda con brisa, Norte sospechoso con menos evidencia que Este
	case_memory.append({
		"pattern": [
			PatternToken.OUT_OF_BOUNDS_OR_WALL, PatternToken.FRONTIER_SUSPICIOUS_PIT, PatternToken.UNKNOWN_CELL,
			PatternToken.VISITED_CALM,          PatternToken.VISITED_BREEZE,          PatternToken.FRONTIER_SUSPICIOUS_PIT,
			PatternToken.VISITED_CALM,          PatternToken.VISITED_BREEZE,          PatternToken.CONFIRMED_HAZARD
		],
		"chosen_dir": Vector2i(0, -1),
		"outcome": "SUCCESS"
	})
	# Caso semilla 2: Agente en celda con brisa al borde izquierdo, avance hacia Este
	case_memory.append({
		"pattern": [
			PatternToken.OUT_OF_BOUNDS_OR_WALL, PatternToken.VISITED_CALM,            PatternToken.FRONTIER_SUSPICIOUS_PIT,
			PatternToken.OUT_OF_BOUNDS_OR_WALL, PatternToken.VISITED_BREEZE,          PatternToken.FRONTIER_SUSPICIOUS_PIT,
			PatternToken.OUT_OF_BOUNDS_OR_WALL, PatternToken.FRONTIER_SUSPICIOUS_PIT, PatternToken.UNKNOWN_CELL
		],
		"chosen_dir": Vector2i(1, 0),
		"outcome": "SUCCESS"
	})
	# Caso semilla 3: Agente frente a sospecha de hedor simple hacia Sur
	case_memory.append({
		"pattern": [
			PatternToken.VISITED_CALM,   PatternToken.VISITED_CALM,               PatternToken.OUT_OF_BOUNDS_OR_WALL,
			PatternToken.VISITED_CALM,   PatternToken.VISITED_STENCH,             PatternToken.FRONTIER_SUSPICIOUS_WUMPUS,
			PatternToken.UNKNOWN_CELL,   PatternToken.FRONTIER_SUSPICIOUS_WUMPUS, PatternToken.UNKNOWN_CELL
		],
		"chosen_dir": Vector2i(0, 1),
		"outcome": "SUCCESS"
	})
	# Caso semilla 4: Agente rodeado de brisa, salida lateral derecha exitosa
	case_memory.append({
		"pattern": [
			PatternToken.VISITED_BREEZE, PatternToken.CONFIRMED_HAZARD,        PatternToken.UNKNOWN_CELL,
			PatternToken.VISITED_CALM,   PatternToken.VISITED_BREEZE,          PatternToken.FRONTIER_SUSPICIOUS_PIT,
			PatternToken.VISITED_CALM,   PatternToken.FRONTIER_SUSPICIOUS_PIT, PatternToken.UNKNOWN_CELL
		],
		"chosen_dir": Vector2i(1, 0),
		"outcome": "SUCCESS"
	})

func extract_3x3_pattern(epistemic_map: EpistemicMapData, center_cell: Vector2i) -> Array[int]:
	var pattern: Array[int] = []
	for offset: Vector2i in WINDOW_OFFSETS:
		var target: Vector2i = center_cell + offset
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

# 1. RETRIEVE & 2. REUSE
func select_risky_frontier_cell(
	epistemic_map: EpistemicMapData,
	nav_planner: NavigationPlannerAStar,
	suspicious_frontiers: Array[Vector2i],
	turn_number: int
) -> Dictionary:
	if suspicious_frontiers.is_empty():
		return {"has_target": false, "target_cell": Vector2i(-1, -1), "path": [] as Array[Vector2i]}

	var current_pattern: Array[int] = extract_3x3_pattern(epistemic_map, epistemic_map.agent_pos)

	# 1. RETRIEVE: Buscar el caso historico exitoso con mayor similitud
	var best_sim: float = -1.0
	var best_case_idx: int = -1
	var best_dir: Vector2i = Vector2i.ZERO

	for idx: int in range(case_memory.size()):
		var c_entry: Dictionary = case_memory[idx]
		if String(c_entry.get("outcome", "")) != "SUCCESS":
			continue
		var c_pattern: Array = c_entry.get("pattern", [])
		var sim: float = compute_weighted_similarity(current_pattern, c_pattern)
		var candidate_cell: Vector2i = epistemic_map.agent_pos + (c_entry.get("chosen_dir", Vector2i.ZERO) as Vector2i)
		if suspicious_frontiers.has(candidate_cell) and sim > best_sim:
			best_sim = sim
			best_case_idx = idx
			best_dir = c_entry.get("chosen_dir", Vector2i.ZERO) as Vector2i

	# 2. REUSE: Si supera el umbral de 0.60, reutilizamos la direccion sugerida
	if best_sim >= SIMILARITY_THRESHOLD and best_case_idx != -1:
		var chosen_cell: Vector2i = epistemic_map.agent_pos + best_dir
		var path_to_chosen: Array[Vector2i] = nav_planner.compute_grid_path(epistemic_map.agent_pos, chosen_cell)
		if not path_to_chosen.is_empty():
			_start_episode(current_pattern, best_dir, best_sim, best_case_idx)
			var msg: String = "Ciclo 4R [RETRIEVE/REUSE]: Caso #%d recuperado (Similitud = %.2f >= 0.60). Asumiendo riesgo controlado hacia %s." % [
				best_case_idx + 1, best_sim, str(chosen_cell)
			]
			EventBus.xai_cbr_triggered.emit(turn_number, best_sim, chosen_cell, msg)
			return {
				"has_target": true,
				"target_cell": chosen_cell,
				"path": path_to_chosen,
				"similarity": best_sim
			}

	# Fallback Heuristico (Seccion 3.3.2): Seleccionar la celda SUSPICIOUS alcanzable
	# con menor cantidad de casillas visitadas con brisa/hedor alrededor y menor distancia.
	var best_fallback_cell: Vector2i = Vector2i(-1, -1)
	var best_fallback_path: Array[Vector2i] = []
	var lowest_danger_score: float = INF
	var max_any_sim: float = 0.0
	for idx: int in range(case_memory.size()):
		var c_entry: Dictionary = case_memory[idx]
		var s: float = compute_weighted_similarity(current_pattern, c_entry.get("pattern", []))
		if s > max_any_sim:
			max_any_sim = s

	for cand: Vector2i in suspicious_frontiers:
		var cand_path: Array[Vector2i] = nav_planner.compute_grid_path(epistemic_map.agent_pos, cand)
		if cand_path.is_empty():
			continue
		var warn_neighbors: int = _count_warning_visited_neighbors(epistemic_map, cand)
		var dist_steps: int = cand_path.size() - 1
		var score: float = float(warn_neighbors) * 10.0 + float(dist_steps)
		if score < lowest_danger_score:
			lowest_danger_score = score
			best_fallback_cell = cand
			best_fallback_path = cand_path

	if best_fallback_cell != Vector2i(-1, -1):
		var first_step_dir: Vector2i = Vector2i.ZERO
		if best_fallback_path.size() >= 2:
			first_step_dir = best_fallback_path[1] - epistemic_map.agent_pos
		var eval_pattern: Array[int] = extract_3x3_pattern(epistemic_map, best_fallback_path[best_fallback_path.size() - 2] if best_fallback_path.size() >= 2 else epistemic_map.agent_pos)
		var final_dir: Vector2i = best_fallback_cell - (best_fallback_path[best_fallback_path.size() - 2] if best_fallback_path.size() >= 2 else epistemic_map.agent_pos)
		_start_episode(eval_pattern, final_dir, max_any_sim, -1)

		var reason: String = "Ciclo 4R [REUSE-HEURISTICO]: Similitud maxima %.2f < 0.60. Elegida celda sospechosa %s por menor indice de brisa/hedor adyacente." % [
			max_any_sim, str(best_fallback_cell)
		]
		EventBus.xai_cbr_triggered.emit(turn_number, max_any_sim, best_fallback_cell, reason)
		return {
			"has_target": true,
			"target_cell": best_fallback_cell,
			"path": best_fallback_path,
			"similarity": max_any_sim,
			"first_step_dir": first_step_dir
		}

	return {"has_target": false, "target_cell": Vector2i(-1, -1), "path": [] as Array[Vector2i]}

func _count_warning_visited_neighbors(epistemic_map: EpistemicMapData, cell: Vector2i) -> int:
	var count: int = 0
	for n_pos: Vector2i in epistemic_map.get_orthogonal_neighbors(cell):
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

# 3. REVISE & 4. RETAIN
func revise_and_retain_episode(survived: bool, stepped_cell: Vector2i, turn_number: int) -> void:
	if not _has_active_episode:
		return

	var outcome_str: String = "SUCCESS" if survived else "FAILURE"
	var previous_failed: bool = false

	# 3. REVISE: Actualizar caso previo si fue reutilizado y fallo
	if _active_episode_matched_index >= 0 and _active_episode_matched_index < case_memory.size():
		if not survived:
			case_memory[_active_episode_matched_index]["outcome"] = "FAILURE"
			previous_failed = true

	# 4. RETAIN: Retener nuevo episodio si similitud < 0.85 o si fallo un caso previo
	if _active_episode_similarity < RETAIN_SIMILARITY_CEILING or previous_failed or not survived:
		case_memory.append({
			"pattern": _active_episode_pattern.duplicate(),
			"chosen_dir": _active_episode_dir,
			"outcome": outcome_str
		})
		var retain_msg: String = "Ciclo 4R [REVISE/RETAIN]: Episodio en %s evaluado como %s (Sim=%.2f). Caso retenido en memoria (Total casos: %d)." % [
			str(stepped_cell), outcome_str, _active_episode_similarity, case_memory.size()
		]
		EventBus.xai_cbr_triggered.emit(turn_number, _active_episode_similarity, stepped_cell, retain_msg)

	_has_active_episode = false
