class_name RuleEngineRBR
extends RefCounted
## Motor de IA: RuleEngineRBR
## Sistema Experto Basado en Reglas (Forward Chaining de Punto Fijo) multipiso
## mejorado con:
##   - Deduccion CSP exacta estilo Buscaminas (componentes conexas de frontera)
##     para deducir Pozos y Wumpus por eliminacion/subconjuntos y calcular
##     probabilidades exactas P(Pozo) y P(Wumpus).
##   - Soporte para multiples Wumpus (matar uno re-muestrea hedores en lugar de
##     asumir que no quedan otros Wumpus vivos).
##   - Recogida de Flechas en el mapa y descubrimiento de Portales y Escaleras.

const PIT_PRIOR_PROB: float = 0.20
const WUMPUS_PRIOR_PROB: float = 0.15
const MAX_CSP_COMPONENT_VARS: int = 12

var _announced_keys: Dictionary = {} # String -> bool

func clear_announced_history() -> void:
	_announced_keys.clear()

func _emit_xai_once(turn_number: int, rule_code: String, ded_key: String, message: String) -> void:
	if _announced_keys.has(ded_key):
		return
	_announced_keys[ded_key] = true
	EventBus.xai_rule_triggered.emit(turn_number, rule_code, message)

func _fmt(c: Vector3i) -> String:
	return "(%d,%d,P%d)" % [c.x, c.y, c.z + 1]

func run_forward_chaining(
	epistemic_map: EpistemicMapData,
	nav_planner: NavigationPlannerAStar,
	world_truth: WorldTruthData,
	turn_number: int
) -> Dictionary:
	var confirmed_wumpus_cells: Array[Vector3i] = []
	var arrow_shot_performed: bool = false
	var arrow_target_cell: Vector3i = Vector3i(-1, -1, -1)
	var arrow_hit_success: bool = false

	# Inicializar solidez base en AStar
	for pos: Vector3i in epistemic_map.cells.keys():
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

	# Habilitar destinos descubiertos de Portales y Escaleras (son construidos en celdas sin pozo/muro)
	for link: Array in epistemic_map.known_special_links:
		for endpoint_var: Variant in link:
			var ep: Vector3i = endpoint_var as Vector3i
			var ep_cell: CellBeliefData = epistemic_map.get_cell(ep)
			if ep_cell != null and not ep_cell.is_wall and ep_cell.overall_state != GameConstants.OverallState.CONFIRMED_HAZARD:
				if ep_cell.pit_state == GameConstants.FactState.UNKNOWN:
					ep_cell.pit_state = GameConstants.FactState.SAFE
				if ep_cell.wumpus_state == GameConstants.FactState.UNKNOWN:
					ep_cell.wumpus_state = GameConstants.FactState.SAFE
				ep_cell.overall_state = GameConstants.OverallState.SAFE
				nav_planner.mark_cell_safe(ep)
				_emit_xai_once(
					turn_number,
					"LINK",
					"LINK_%s" % [str(ep)],
					"Acceso especial (Portal/Escalera) habilita ruta hacia %s." % [_fmt(ep)]
				)

	# Bucle de Punto Fijo (Forward Chaining R1 a R6 + Buscaminas CSP)
	var deduction_made: bool = true
	var iteration_guard: int = 0
	while deduction_made and iteration_guard < 48:
		deduction_made = false
		iteration_guard += 1

		# Regla R1 (Descarte de Pozo) y Regla R2 (Descarte de Wumpus)
		for v_pos: Vector3i in epistemic_map.visited_cells:
			var v_cell: CellBeliefData = epistemic_map.get_cell(v_pos)
			if v_cell == null or not v_cell.visited:
				continue

			var neighbors: Array[Vector3i] = epistemic_map.get_passable_orthogonal_neighbors(v_pos)

			if not v_cell.breeze:
				for n_pos: Vector3i in neighbors:
					var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
					if n_cell.pit_state != GameConstants.FactState.SAFE:
						n_cell.pit_state = GameConstants.FactState.SAFE
						n_cell.pit_probability = 0.0
						deduction_made = true
						_emit_xai_once(
							turn_number,
							"R1",
							"R1_%s" % [str(n_pos)],
							"Sin brisa en %s descarta Pozo en %s." % [_fmt(v_pos), _fmt(n_pos)]
						)

			if not v_cell.stench:
				for n_pos: Vector3i in neighbors:
					var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
					if n_cell.wumpus_state != GameConstants.FactState.SAFE:
						n_cell.wumpus_state = GameConstants.FactState.SAFE
						n_cell.wumpus_probability = 0.0
						deduction_made = true
						_emit_xai_once(
							turn_number,
							"R2",
							"R2_%s" % [str(n_pos)],
							"Sin hedor en %s descarta Wumpus en %s." % [_fmt(v_pos), _fmt(n_pos)]
						)

		# Regla R4 (Propagacion de Sospecha)
		for v_pos: Vector3i in epistemic_map.visited_cells:
			var v_cell: CellBeliefData = epistemic_map.get_cell(v_pos)
			if v_cell == null or not v_cell.visited:
				continue
			if not v_cell.breeze and not v_cell.stench:
				continue

			for n_pos: Vector3i in epistemic_map.get_passable_orthogonal_neighbors(v_pos):
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
						"Brisa en %s marca %s como SOSPECHOSA de Pozo." % [_fmt(v_pos), _fmt(n_pos)]
					)

				if v_cell.stench and n_cell.wumpus_state == GameConstants.FactState.UNKNOWN:
					n_cell.wumpus_state = GameConstants.FactState.SUSPICIOUS
					deduction_made = true
					_emit_xai_once(
						turn_number,
						"R4",
						"R4_WUMPUS_%s" % [str(n_pos)],
						"Hedor en %s marca %s como SOSPECHOSA de Wumpus." % [_fmt(v_pos), _fmt(n_pos)]
					)

		# Regla R5 (Eliminacion deductiva directa de Pozo)
		for v_pos: Vector3i in epistemic_map.visited_cells:
			var v_cell: CellBeliefData = epistemic_map.get_cell(v_pos)
			if v_cell == null or not v_cell.visited or not v_cell.breeze:
				continue

			var candidates: Array[Vector3i] = []
			for n_pos: Vector3i in epistemic_map.get_passable_orthogonal_neighbors(v_pos):
				var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
				if n_cell.pit_state != GameConstants.FactState.SAFE:
					candidates.append(n_pos)

			if candidates.size() == 1:
				var pit_pos: Vector3i = candidates[0]
				var pit_cell: CellBeliefData = epistemic_map.get_cell(pit_pos)
				if pit_cell.pit_state != GameConstants.FactState.CONFIRMED:
					pit_cell.pit_state = GameConstants.FactState.CONFIRMED
					pit_cell.pit_probability = 1.0
					pit_cell.overall_state = GameConstants.OverallState.CONFIRMED_HAZARD
					nav_planner.mark_cell_hazard_or_wall(pit_pos)
					deduction_made = true
					_emit_xai_once(
						turn_number,
						"R5",
						"R5_%s" % [str(pit_pos)],
						"Eliminacion desde %s confirma POZO en %s." % [_fmt(v_pos), _fmt(pit_pos)]
					)

		# Regla R6 (Localizacion de multiples Wumpus + Disparo de Flecha)
		for v_pos: Vector3i in epistemic_map.visited_cells:
			var v_cell: CellBeliefData = epistemic_map.get_cell(v_pos)
			if v_cell == null or not v_cell.visited or not v_cell.stench:
				continue

			var w_candidates: Array[Vector3i] = []
			for n_pos: Vector3i in epistemic_map.get_passable_orthogonal_neighbors(v_pos):
				var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
				if n_cell.wumpus_state != GameConstants.FactState.SAFE:
					w_candidates.append(n_pos)

			if w_candidates.size() == 1:
				var w_pos: Vector3i = w_candidates[0]
				var w_cell: CellBeliefData = epistemic_map.get_cell(w_pos)
				if not confirmed_wumpus_cells.has(w_pos):
					confirmed_wumpus_cells.append(w_pos)
				if w_cell.wumpus_state != GameConstants.FactState.CONFIRMED:
					w_cell.wumpus_state = GameConstants.FactState.CONFIRMED
					w_cell.wumpus_probability = 1.0
					deduction_made = true
					_emit_xai_once(
						turn_number,
						"R6",
						"R6_LOC_%s" % [str(w_pos)],
						"Triangulacion desde %s confirma WUMPUS en %s." % [_fmt(v_pos), _fmt(w_pos)]
					)

				# Disparar si tenemos flechas y linea ortogonal libre en el mismo piso
				if epistemic_map.arrow_count > 0 and _has_clear_orthogonal_line_of_fire(epistemic_map, epistemic_map.agent_pos, w_pos):
					var shot_ok: bool = fire_arrow_at(epistemic_map, world_truth, w_pos, turn_number)
					arrow_shot_performed = true
					arrow_target_cell = w_pos
					arrow_hit_success = shot_ok
					if shot_ok:
						confirmed_wumpus_cells.erase(w_pos)
						deduction_made = true

		# Deduccion CSP Estilo Buscaminas (Probabilidades + Inferencia de Subconjuntos)
		if _run_minesweeper_csp_deduction(epistemic_map, true, turn_number):
			deduction_made = true
		if _run_minesweeper_csp_deduction(epistemic_map, false, turn_number):
			deduction_made = true

		# Reevaluacion de casillas sospechosas cuando sus brisas/hedores ya estan
		# explicados por un Pozo o Wumpus CONFIRMED (manteniendo riesgo residual de pozo contiguo)
		_reevaluate_explained_suspicious_cells(epistemic_map, turn_number)

		# Regla R3 (Certificacion de Celda Segura) y consolidacion en ambos AStar (Safe-Only y Risk)
		for pos: Vector3i in epistemic_map.cells.keys():
			var cell: CellBeliefData = epistemic_map.get_cell(pos)
			if cell.is_wall:
				if cell.overall_state != GameConstants.OverallState.CONFIRMED_HAZARD:
					cell.overall_state = GameConstants.OverallState.CONFIRMED_HAZARD
					deduction_made = true
				nav_planner.mark_cell_hazard_or_wall(pos)
				continue

			if cell.pit_state == GameConstants.FactState.CONFIRMED or cell.wumpus_state == GameConstants.FactState.CONFIRMED:
				if cell.overall_state != GameConstants.OverallState.CONFIRMED_HAZARD:
					cell.overall_state = GameConstants.OverallState.CONFIRMED_HAZARD
					deduction_made = true
				nav_planner.mark_cell_hazard_or_wall(pos)
				continue

			if cell.pit_state == GameConstants.FactState.SAFE and cell.wumpus_state == GameConstants.FactState.SAFE:
				if cell.overall_state != GameConstants.OverallState.SAFE:
					cell.overall_state = GameConstants.OverallState.SAFE
					deduction_made = true
					if not cell.visited:
						_emit_xai_once(
							turn_number,
							"R3",
							"R3_%s" % [str(pos)],
							"Celda %s certificada 100%% SEGURA." % [_fmt(pos)]
						)
				nav_planner.mark_cell_safe(pos)
				continue

			if cell.pit_state == GameConstants.FactState.SUSPICIOUS or cell.wumpus_state == GameConstants.FactState.SUSPICIOUS:
				if cell.overall_state != GameConstants.OverallState.SUSPICIOUS:
					cell.overall_state = GameConstants.OverallState.SUSPICIOUS
					deduction_made = true
				var pit_ok: bool = (cell.pit_state != GameConstants.FactState.SUSPICIOUS) or cell.pit_explained_by_confirmed
				var wump_ok: bool = (cell.wumpus_state != GameConstants.FactState.SUSPICIOUS) or cell.wumpus_explained_by_confirmed
				if pit_ok and wump_ok:
					nav_planner.mark_cell_low_risk_explained(pos)
				else:
					nav_planner.mark_cell_suspicious(pos)

	return {
		"confirmed_wumpus_cells": confirmed_wumpus_cells,
		"arrow_shot_performed": arrow_shot_performed,
		"arrow_target_cell": arrow_target_cell,
		"arrow_hit_success": arrow_hit_success
	}

func fire_arrow_at(
	epistemic_map: EpistemicMapData,
	world_truth: WorldTruthData,
	target_cell: Vector3i,
	turn_number: int
) -> bool:
	if epistemic_map.arrow_count <= 0:
		return false
	epistemic_map.arrow_count -= 1
	EventBus.agent_inventory_updated.emit(epistemic_map.arrow_count, epistemic_map.has_gold)

	var hit_res: Dictionary = world_truth.check_arrow_hit(epistemic_map.agent_pos, target_cell)
	var hit_ok: bool = bool(hit_res.get("hit", false))
	var hit_cell: Vector3i = hit_res.get("hit_cell", Vector3i(-1, -1, -1)) as Vector3i

	if hit_ok and hit_cell.x >= 0:
		EventBus.xai_rule_triggered.emit(
			turn_number,
			"R6",
			"¡Flecha desde %s abatio WUMPUS en %s! (Flechas restantes: %d)" % [
				_fmt(epistemic_map.agent_pos), _fmt(hit_cell), epistemic_map.arrow_count
			]
		)
		# Re-muestrear hedores de todas las celdas visitadas en ese piso (puede haber otros Wumpus vivos!)
		_refresh_floor_wumpus_beliefs_after_kill(epistemic_map, world_truth, hit_cell)
	else:
		EventBus.xai_rule_triggered.emit(
			turn_number,
			"R6",
			"Flecha disparada hacia %s sin impacto (Flechas restantes: %d)." % [
				_fmt(target_cell), epistemic_map.arrow_count
			]
		)
		# Si la flecha atraveso target_cell sin golpear nada, sabemos que en target_cell NO hay Wumpus vivo!
		var t_cell: CellBeliefData = epistemic_map.get_cell(target_cell)
		if t_cell != null:
			t_cell.wumpus_state = GameConstants.FactState.SAFE
			t_cell.wumpus_probability = 0.0

	EventBus.agent_arrow_fired.emit(Vector2i(epistemic_map.agent_pos.x, epistemic_map.agent_pos.y), Vector2i(target_cell.x, target_cell.y), hit_ok)
	EventBus.agent_arrow_fired_3d.emit(epistemic_map.agent_pos, target_cell, hit_ok)
	return hit_ok

func _refresh_floor_wumpus_beliefs_after_kill(epistemic_map: EpistemicMapData, world_truth: WorldTruthData, killed_cell: Vector3i) -> void:
	var fl: int = killed_cell.z
	for pos: Vector3i in epistemic_map.cells.keys():
		if pos.z != fl:
			continue
		var c: CellBeliefData = epistemic_map.get_cell(pos)
		if c.visited:
			var p: Dictionary = world_truth.sample_percepts_at(pos)
			c.stench = bool(p.get("stench", false))
		elif not c.is_wall:
			c.wumpus_state = GameConstants.FactState.UNKNOWN
			c.wumpus_probability = 0.0
			if c.overall_state == GameConstants.OverallState.CONFIRMED_HAZARD and c.pit_state != GameConstants.FactState.CONFIRMED:
				c.overall_state = GameConstants.OverallState.UNKNOWN

	var killed_belief: CellBeliefData = epistemic_map.get_cell(killed_cell)
	if killed_belief != null:
		killed_belief.wumpus_state = GameConstants.FactState.SAFE
		killed_belief.wumpus_probability = 0.0

func _run_minesweeper_csp_deduction(epistemic_map: EpistemicMapData, is_pit_mode: bool, turn_number: int) -> bool:
	## Solucionador CSP exacto estilo Buscaminas por componentes conexas de frontera.
	## Evalua restricciones de todas las casillas con brisa/hedor simultaneamente:
	##   - Si una casilla tiene peligro en el 100% de modelos validos -> CONFIRMED.
	##   - Si una casilla tiene peligro en el 0% de modelos validos -> SAFE.
	##   - En cualquier otro caso guarda su probabilidad exacta P(peligro) para
	##     evitar decisiones ciegas si llega a ser necesario arriesgar.
	var made_deduction: bool = false
	var prior: float = PIT_PRIOR_PROB if is_pit_mode else WUMPUS_PRIOR_PROB

	for fl: int in range(epistemic_map.floor_count):
		var constraints: Array[Array] = [] # Cada restriccion = Array[Vector3i] de celdas sospechosas (al menos 1 debe tener peligro)
		var frontier_vars: Array[Vector3i] = []

		for v_pos: Vector3i in epistemic_map.visited_cells:
			if v_pos.z != fl:
				continue
			var v_cell: CellBeliefData = epistemic_map.get_cell(v_pos)
			if v_cell == null or not v_cell.visited:
				continue
			var has_signal: bool = v_cell.breeze if is_pit_mode else v_cell.stench
			if not has_signal:
				continue

			var already_explained: bool = false
			var susp_neighbors: Array[Vector3i] = []
			for n_pos: Vector3i in epistemic_map.get_passable_orthogonal_neighbors(v_pos):
				var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
				var st: int = n_cell.pit_state if is_pit_mode else n_cell.wumpus_state
				if st == GameConstants.FactState.CONFIRMED:
					already_explained = true
					break
				elif st != GameConstants.FactState.SAFE:
					susp_neighbors.append(n_pos)

			if already_explained or susp_neighbors.is_empty():
				continue
			constraints.append(susp_neighbors)
			for sv: Vector3i in susp_neighbors:
				if not frontier_vars.has(sv):
					frontier_vars.append(sv)

		if frontier_vars.is_empty():
			continue

		# Agrupar variables en componentes conexas que comparten restricciones
		var visited_var: Dictionary = {}
		for seed_var: Vector3i in frontier_vars:
			if visited_var.has(seed_var):
				continue
			var comp_vars: Array[Vector3i] = []
			var queue: Array[Vector3i] = [seed_var]
			visited_var[seed_var] = true
			while not queue.is_empty():
				var cur: Vector3i = queue.pop_front() as Vector3i
				comp_vars.append(cur)
				for cons: Array in constraints:
					if cons.has(cur):
						for other_v: Variant in cons:
							var ov: Vector3i = other_v as Vector3i
							if not visited_var.has(ov):
								visited_var[ov] = true
								queue.append(ov)

			var comp_constraints: Array[Array] = []
			for cons: Array in constraints:
				for item: Variant in cons:
					if comp_vars.has(item as Vector3i):
						comp_constraints.append(cons)
						break

			var k: int = comp_vars.size()
			if k > MAX_CSP_COMPONENT_VARS:
				# Aproximacion heuristica rapida si la componente es muy grande (>12 variables)
				for cv: Vector3i in comp_vars:
					var c_b: CellBeliefData = epistemic_map.get_cell(cv)
					var deg: int = 0
					for cons: Array in comp_constraints:
						if cons.has(cv):
							deg += 1
					var est_p: float = clampf(0.25 * float(deg), 0.15, 0.92)
					if is_pit_mode:
						c_b.pit_probability = est_p
					else:
						c_b.wumpus_probability = est_p
				continue

			# Enumeracion exacta de los 2^k modelos validos de la componente
			var total_weight: float = 0.0
			var var_true_weight: Array[float] = []
			for _i: int in range(k):
				var_true_weight.append(0.0)

			var total_masks: int = 1 << k
			for mask: int in range(total_masks):
				var valid_model: bool = true
				for cons: Array in comp_constraints:
					var satisfied: bool = false
					for v_elem: Variant in cons:
						var v_idx: int = comp_vars.find(v_elem as Vector3i)
						if v_idx >= 0 and ((mask & (1 << v_idx)) != 0):
							satisfied = true
							break
					if not satisfied:
						valid_model = false
						break

				if not valid_model:
					continue

				# Peso bayesiano del modelo segun probabilidad a priori
				var model_w: float = 1.0
				for i: int in range(k):
					if (mask & (1 << i)) != 0:
						model_w *= prior
					else:
						model_w *= (1.0 - prior)

				total_weight += model_w
				for i: int in range(k):
					if (mask & (1 << i)) != 0:
						var_true_weight[i] += model_w

			if total_weight <= 0.0:
				continue

			for i: int in range(k):
				var prob: float = var_true_weight[i] / total_weight
				var cell_pos: Vector3i = comp_vars[i]
				var belief: CellBeliefData = epistemic_map.get_cell(cell_pos)
				if is_pit_mode:
					belief.pit_probability = prob
					if prob >= 0.9999 and belief.pit_state != GameConstants.FactState.CONFIRMED:
						belief.pit_state = GameConstants.FactState.CONFIRMED
						made_deduction = true
						_emit_xai_once(
							turn_number,
							"CSP-PIT",
							"CSP_PIT_%s" % [str(cell_pos)],
							"Deduccion Buscaminas confirma POZO en %s (100%% de modelos)." % [_fmt(cell_pos)]
						)
					elif prob <= 0.0001 and belief.pit_state != GameConstants.FactState.SAFE:
						belief.pit_state = GameConstants.FactState.SAFE
						made_deduction = true
						_emit_xai_once(
							turn_number,
							"CSP-SAFE",
							"CSP_SAFE_P_%s" % [str(cell_pos)],
							"Deduccion Buscaminas descarta Pozo en %s (0%% de modelos)." % [_fmt(cell_pos)]
						)
				else:
					belief.wumpus_probability = prob
					if prob >= 0.9999 and belief.wumpus_state != GameConstants.FactState.CONFIRMED:
						belief.wumpus_state = GameConstants.FactState.CONFIRMED
						made_deduction = true
						_emit_xai_once(
							turn_number,
							"CSP-WUMP",
							"CSP_W_%s" % [str(cell_pos)],
							"Deduccion Buscaminas confirma WUMPUS en %s (100%% de modelos)." % [_fmt(cell_pos)]
						)
					elif prob <= 0.0001 and belief.wumpus_state != GameConstants.FactState.SAFE:
						belief.wumpus_state = GameConstants.FactState.SAFE
						made_deduction = true

	return made_deduction

func evaluate_rule_r7_gold_and_arrows(
	epistemic_map: EpistemicMapData,
	world_truth: WorldTruthData,
	turn_number: int
) -> Dictionary:
	var gold_captured: bool = false
	var arrow_picked: bool = false

	var current_cell: CellBeliefData = epistemic_map.get_cell(epistemic_map.agent_pos)
	if current_cell != null and current_cell.glitter and not epistemic_map.has_gold:
		epistemic_map.has_gold = true
		world_truth.gold_collected = true
		current_cell.glitter = false
		gold_captured = true
		EventBus.xai_rule_triggered.emit(
			turn_number,
			"R7",
			"¡Lingote de Oro capturado en %s! Calculando ruta de extraccion segura a (0,0,P1)." % [_fmt(epistemic_map.agent_pos)]
		)

	if world_truth.collect_arrow_at(epistemic_map.agent_pos):
		epistemic_map.arrow_count += 1
		arrow_picked = true
		EventBus.xai_rule_triggered.emit(
			turn_number,
			"ARROW",
			"Flecha recogida en %s (Municion total: %d)." % [_fmt(epistemic_map.agent_pos), epistemic_map.arrow_count]
		)

	if gold_captured or arrow_picked:
		EventBus.agent_inventory_updated.emit(epistemic_map.arrow_count, epistemic_map.has_gold)

	return {"gold_captured": gold_captured, "arrow_picked": arrow_picked}

func _reevaluate_explained_suspicious_cells(epistemic_map: EpistemicMapData, turn_number: int) -> void:
	## Reevalua cada celda sospechosa: si TODAS las casillas visitadas con brisa/hedor
	## adyacentes ya tienen un peligro CONFIRMED que explica esa percepcion, la celda
	## pasa a riesgo residual bajo (posible pozo/wumpus contiguo, probabilidad a priori)
	## en vez de tratarse como peligro alto sin explicar.
	for pos: Vector3i in epistemic_map.cells.keys():
		var cell: CellBeliefData = epistemic_map.get_cell(pos)
		if cell.visited or cell.is_wall:
			continue

		if cell.pit_state == GameConstants.FactState.SUSPICIOUS:
			var has_breeze_adj: bool = false
			var all_breezes_explained: bool = true
			for n_pos: Vector3i in epistemic_map.get_orthogonal_neighbors(pos):
				var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
				if n_cell != null and n_cell.visited and n_cell.breeze:
					has_breeze_adj = true
					if not _cell_has_confirmed_hazard_neighbor(epistemic_map, n_pos, true):
						all_breezes_explained = false
						break
			if has_breeze_adj and all_breezes_explained:
				cell.pit_explained_by_confirmed = true
				cell.pit_probability = PIT_PRIOR_PROB
				_emit_xai_once(
					turn_number,
					"REEVAL",
					"REEVAL_PIT_%s" % [str(pos)],
					"Pozo confirmado explica brisa junto a %s: riesgo baja a %d%% (pozo contiguo posible)." % [
						_fmt(pos), int(round(PIT_PRIOR_PROB * 100.0))
					]
				)
			else:
				cell.pit_explained_by_confirmed = false

		if cell.wumpus_state == GameConstants.FactState.SUSPICIOUS:
			var has_stench_adj: bool = false
			var all_stenches_explained: bool = true
			for n_pos: Vector3i in epistemic_map.get_orthogonal_neighbors(pos):
				var n_cell: CellBeliefData = epistemic_map.get_cell(n_pos)
				if n_cell != null and n_cell.visited and n_cell.stench:
					has_stench_adj = true
					if not _cell_has_confirmed_hazard_neighbor(epistemic_map, n_pos, false):
						all_stenches_explained = false
						break
			if has_stench_adj and all_stenches_explained:
				cell.wumpus_explained_by_confirmed = true
				cell.wumpus_probability = WUMPUS_PRIOR_PROB
				_emit_xai_once(
					turn_number,
					"REEVAL",
					"REEVAL_W_%s" % [str(pos)],
					"Wumpus confirmado explica hedor junto a %s: riesgo baja a %d%%." % [
						_fmt(pos), int(round(WUMPUS_PRIOR_PROB * 100.0))
					]
				)
			else:
				cell.wumpus_explained_by_confirmed = false

func _cell_has_confirmed_hazard_neighbor(epistemic_map: EpistemicMapData, visited_cell: Vector3i, check_pit: bool) -> bool:
	for nb: Vector3i in epistemic_map.get_passable_orthogonal_neighbors(visited_cell):
		var nb_cell: CellBeliefData = epistemic_map.get_cell(nb)
		if nb_cell == null:
			continue
		if check_pit and nb_cell.pit_state == GameConstants.FactState.CONFIRMED:
			return true
		if (not check_pit) and nb_cell.wumpus_state == GameConstants.FactState.CONFIRMED:
			return true
	return false

func reconstruct_epistemic_state_r8(
	epistemic_map: EpistemicMapData,
	nav_planner: NavigationPlannerAStar,
	world_truth: WorldTruthData,
	turn_number: int,
	edit_reason: String
) -> Dictionary:
	_announced_keys.clear()

	if not world_truth.gold_collected:
		epistemic_map.has_gold = false

	epistemic_map.clear_special_links()

	var valid_visited: Array[Vector3i] = []
	for v_pos: Vector3i in epistemic_map.visited_cells:
		if not epistemic_map.is_within_bounds(v_pos):
			continue
		if world_truth.has_wall(v_pos):
			var w_belief: CellBeliefData = epistemic_map.get_cell(v_pos)
			if w_belief != null:
				w_belief.visited = false
				w_belief.is_wall = true
			continue
		valid_visited.append(v_pos)

	epistemic_map.visited_cells = valid_visited

	for pos: Vector3i in epistemic_map.cells.keys():
		var c: CellBeliefData = epistemic_map.get_cell(pos)
		if c.is_wall and not world_truth.has_wall(pos):
			c.is_wall = false

	for v_pos: Vector3i in epistemic_map.visited_cells:
		var percepts: Dictionary = world_truth.sample_percepts_at(v_pos)
		var belief: CellBeliefData = epistemic_map.get_cell(v_pos)
		if belief != null:
			belief.breeze = bool(percepts.get("breeze", false))
			belief.stench = bool(percepts.get("stench", false))
			belief.glitter = bool(percepts.get("glitter", false))
			var adj_walls: Array = percepts.get("adjacent_walls", [])
			for w_var: Variant in adj_walls:
				var w_pos: Vector3i = w_var as Vector3i
				if epistemic_map.is_within_bounds(w_pos):
					epistemic_map.mark_wall_state(w_pos, true)
			var spec_dests: Array = percepts.get("special_destinations", [])
			for d_var: Variant in spec_dests:
				var dest: Vector3i = d_var as Vector3i
				if dest.x >= 0:
					epistemic_map.register_special_link(v_pos, dest)

	epistemic_map.reset_non_visited_deductions()

	EventBus.xai_rule_triggered.emit(
		turn_number,
		"R8",
		"Revision Epistemica (%s). Base de hechos reconstruida." % [edit_reason]
	)

	return run_forward_chaining(epistemic_map, nav_planner, world_truth, turn_number)

func _has_clear_orthogonal_line_of_fire(epistemic_map: EpistemicMapData, from_cell: Vector3i, target_cell: Vector3i) -> bool:
	if from_cell.z != target_cell.z:
		return false
	var delta: Vector2i = Vector2i(target_cell.x - from_cell.x, target_cell.y - from_cell.y)
	if delta == Vector2i.ZERO:
		return false
	if delta.x != 0 and delta.y != 0:
		return false
	var step: Vector2i = Vector2i(signi(delta.x), signi(delta.y))
	var cursor: Vector3i = Vector3i(from_cell.x + step.x, from_cell.y + step.y, from_cell.z)
	while epistemic_map.is_within_bounds(cursor):
		var belief: CellBeliefData = epistemic_map.get_cell(cursor)
		if belief != null and belief.is_wall:
			return false
		if cursor == target_cell:
			return true
		cursor = Vector3i(cursor.x + step.x, cursor.y + step.y, cursor.z)
	return false
