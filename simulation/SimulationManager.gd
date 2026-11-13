class_name SimulationManager
extends Node
## Controlador de Simulacion: SimulationManager
## Gestiona el ciclo de turnos discretos en 3 fases pausadas estilo Ajedrez:
##   Fase A: Observacion, Inferencia XAI y actualizacion de ruta (THINK_DELAY = 0.55 s)
##   Fase B: Movimiento parabolico estilo pieza de ajedrez (CHESS_MOVE_DURATION = 0.85 s)
##   Fase C: Asentamiento fisico en la baldosa (SETTLE_DELAY = 0.35 s)
## Garantiza cero condiciones de carrera ante ediciones en vivo del Modo Dios (Regla 6).

enum TurnPhase {
	IDLE,
	PHASE_A_THINKING,
	PHASE_B_MOVING,
	PHASE_C_SETTLING
}

var world_truth: WorldTruthData
var knowledge_engine: KnowledgeEngine

var sim_state: GameConstants.SimState = GameConstants.SimState.PAUSED
var turn_phase: TurnPhase = TurnPhase.IDLE
var speed_multiplier: float = 1.0

var turn_number: int = 0
var is_step_in_progress: bool = false
var _step_origin_cell: Vector2i = Vector2i.ZERO
var _step_target_cell: Vector2i = Vector2i.ZERO
var _pending_god_edits_reasons: Array[String] = []
var _was_running_before_wait: bool = false

var _phase_tween: Tween

func _ready() -> void:
	world_truth = WorldTruthData.new(GameConstants.DEFAULT_GRID_SIZE)
	knowledge_engine = KnowledgeEngine.new(GameConstants.DEFAULT_GRID_SIZE)

	EventBus.god_action_requested.connect(_on_god_action_requested)
	EventBus.sim_control_requested.connect(_on_sim_control_requested)
	EventBus.board_resize_requested.connect(_on_board_resize_requested)
	EventBus.sim_speed_changed.connect(_on_sim_speed_changed)

	call_deferred("_initialize_simulation", GameConstants.DEFAULT_GRID_SIZE)

func _get_scaled_time(base_seconds: float) -> float:
	var mult: float = clampf(speed_multiplier, 0.25, 4.0)
	return base_seconds / mult

func _on_sim_speed_changed(new_multiplier: float) -> void:
	speed_multiplier = clampf(new_multiplier, 0.25, 4.0)
	GameConstants.current_speed_multiplier = speed_multiplier
	EventBus.xai_rule_triggered.emit(
		turn_number,
		"SPEED",
		"Cadencia de ajedrez ajustada a %.1fx." % [speed_multiplier]
	)

func _initialize_simulation(target_size: Vector2i) -> void:
	_cancel_active_phase_tween()
	is_step_in_progress = false
	turn_phase = TurnPhase.IDLE
	_pending_god_edits_reasons.clear()
	turn_number = 0
	_was_running_before_wait = false

	world_truth.setup_default_scenario(target_size)
	knowledge_engine.reset_knowledge(world_truth.grid_size)

	# Muestreo inicial en (0, 0)
	knowledge_engine.perceive_and_reason_at_current_cell(world_truth, turn_number)
	knowledge_engine.plan_next_route(turn_number)

	EventBus.world_truth_changed.emit(world_truth.to_snapshot())
	knowledge_engine.emit_epistemic_visual_update()
	EventBus.agent_transform_updated.emit(
		knowledge_engine.epistemic_map.agent_pos,
		knowledge_engine.epistemic_map.agent_facing,
		false
	)

	_change_sim_state(
		GameConstants.SimState.PAUSED,
		"Tablero %dx%d inicializado en (0, 0). Cadencia Ajedrez %.1fx lista." % [
			world_truth.grid_size.x, world_truth.grid_size.y, speed_multiplier
		]
	)
	EventBus.xai_rule_triggered.emit(
		0,
		"INIT",
		"Pieza Exploradora posicionada en casilla segura (0, 0). Sensores calibrados."
	)

func _cancel_active_phase_tween() -> void:
	if _phase_tween != null and _phase_tween.is_valid():
		_phase_tween.kill()
	_phase_tween = null

func _change_sim_state(new_state: GameConstants.SimState, message: String) -> void:
	sim_state = new_state
	EventBus.sim_state_changed.emit(sim_state, message)

func _on_board_resize_requested(new_size: Vector2i) -> void:
	_initialize_simulation(new_size)

func _on_sim_control_requested(action: String) -> void:
	match action.to_upper():
		"PLAY":
			if sim_state in [GameConstants.SimState.VICTORY, GameConstants.SimState.GAME_OVER]:
				_initialize_simulation(world_truth.grid_size)
			_was_running_before_wait = true
			_change_sim_state(GameConstants.SimState.RUNNING, "Simulacion en ejecucion (Ritmo de Ajedrez %.1fx)." % [speed_multiplier])
			if not is_step_in_progress:
				_begin_turn_phase_a_deliberation()

		"PAUSE":
			_was_running_before_wait = false
			_change_sim_state(GameConstants.SimState.PAUSED, "Simulacion en pausa.")

		"TOGGLE_PAUSE":
			if sim_state == GameConstants.SimState.RUNNING:
				_on_sim_control_requested("PAUSE")
			else:
				_on_sim_control_requested("PLAY")

		"STEP":
			if sim_state in [GameConstants.SimState.VICTORY, GameConstants.SimState.GAME_OVER]:
				return
			_was_running_before_wait = false
			_change_sim_state(GameConstants.SimState.STEPPING, "Ejecutando movimiento deliberado de pieza...")
			if not is_step_in_progress:
				_begin_turn_phase_a_deliberation()

		"RESET":
			_initialize_simulation(world_truth.grid_size)

func _on_god_action_requested(cell: Vector2i, tool: GameConstants.GodTool) -> void:
	var agent_pos: Vector2i = knowledge_engine.epistemic_map.agent_pos
	var edit_result: Dictionary = world_truth.apply_god_tool(cell, tool, agent_pos)
	var changed: bool = bool(edit_result.get("changed", false))
	var reason: String = String(edit_result.get("reason", ""))

	if not changed:
		EventBus.xai_rule_triggered.emit(turn_number, "GOD-REJECT", reason)
		return

	EventBus.world_truth_changed.emit(world_truth.to_snapshot())

	# Regla 6: Si el agente esta deliberando o moviendose hacia una celda que acaba de convertirse en Muro,
	# cancelamos el paso de inmediato y registramos el muro.
	if is_step_in_progress:
		if cell == _step_target_cell and world_truth.has_wall(cell):
			_cancel_active_phase_tween()
			is_step_in_progress = false
			turn_phase = TurnPhase.IDLE
			knowledge_engine.epistemic_map.agent_pos = _step_origin_cell
			knowledge_engine.epistemic_map.mark_wall_state(cell, true)
			EventBus.agent_transform_updated.emit(
				_step_origin_cell,
				knowledge_engine.epistemic_map.agent_facing,
				false
			)
			knowledge_engine.handle_god_mode_modification(
				world_truth,
				turn_number,
				reason + " (Movimiento de pieza cancelado por nuevo Muro en destino)"
			)
			knowledge_engine.emit_epistemic_visual_update()
			if sim_state == GameConstants.SimState.RUNNING:
				_begin_turn_phase_a_deliberation()
			elif sim_state == GameConstants.SimState.STEPPING:
				_change_sim_state(GameConstants.SimState.PAUSED, "Movimiento cancelado por Muro en %s." % [str(cell)])
			return
		else:
			_pending_god_edits_reasons.append(reason)
			return

	# Si no hay turno en vuelo, aplicamos la reconstruccion epistemica determinista al instante (Regla 5 y R8)
	knowledge_engine.handle_god_mode_modification(world_truth, turn_number, reason)
	knowledge_engine.emit_epistemic_visual_update()

	# Si estaba en WAITING_FOR_GOD_MODE y ahora se abrio una ruta, reactivamos o notificamos
	if sim_state == GameConstants.SimState.WAITING_FOR_GOD_MODE:
		var plan_check: Dictionary = knowledge_engine.plan_next_route(turn_number)
		knowledge_engine.emit_epistemic_visual_update()
		if String(plan_check.get("status", "")) == "HAS_ROUTE":
			if _was_running_before_wait:
				_change_sim_state(GameConstants.SimState.RUNNING, "Camino desbloqueado por Modo Dios. Reanudando partida.")
				_begin_turn_phase_a_deliberation()
			else:
				_change_sim_state(GameConstants.SimState.PAUSED, "Camino desbloqueado por Modo Dios. Listo para continuar.")

# ==============================================================================
# FASE A: PAUSA DE OBSERVACION Y DELIBERACION (THINK_DELAY = 0.55 s base)
# ==============================================================================
func _begin_turn_phase_a_deliberation() -> void:
	if is_step_in_progress:
		return
	if sim_state in [GameConstants.SimState.VICTORY, GameConstants.SimState.GAME_OVER]:
		return

	turn_number += 1
	is_step_in_progress = true
	turn_phase = TurnPhase.PHASE_A_THINKING

	# 1. Leer sensores y ejecutar inferencia R1-R8 / disparo de flecha en la celda actual
	var step_eval: Dictionary = knowledge_engine.perceive_and_reason_at_current_cell(world_truth, turn_number)
	if bool(step_eval.get("arrow_shot_performed", false)):
		EventBus.world_truth_changed.emit(world_truth.to_snapshot())

	# 2. Planificar siguiente movimiento y actualizar colores XAI + linea de ruta en el tablero
	var plan: Dictionary = knowledge_engine.plan_next_route(turn_number)
	knowledge_engine.emit_epistemic_visual_update()

	var status: String = String(plan.get("status", "BLOCKED"))
	if status == "AT_EXTRACTION_WITH_GOLD":
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		_change_sim_state(
			GameConstants.SimState.VICTORY,
			"¡VICTORIA EN TURNO %d! El agente recupero el Oro y regreso a salvo a (0, 0)." % [turn_number]
		)
		EventBus.xai_rule_triggered.emit(
			turn_number,
			"VICTORY",
			"Mision completada con exito en (0, 0) portando el Lingote de Oro."
		)
		return

	if status == "BLOCKED":
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		_change_sim_state(
			GameConstants.SimState.WAITING_FOR_GOD_MODE,
			"BLOQUEO SEGURO: %s" % [String(plan.get("reason", "Rutas bloqueadas."))]
		)
		EventBus.xai_rule_triggered.emit(
			turn_number,
			"WAIT-GOD",
			"Estado WAITING_FOR_GOD_MODE activo: Reloj pausado esperando apertura de camino en Modo Dios."
		)
		return

	_step_origin_cell = knowledge_engine.epistemic_map.agent_pos
	_step_target_cell = plan.get("next_cell", _step_origin_cell) as Vector2i

	# Esperar THINK_DELAY para que el espectador observe las deducciones XAI y la ruta antes de levantar la pieza
	_cancel_active_phase_tween()
	_phase_tween = create_tween()
	_phase_tween.tween_interval(_get_scaled_time(GameConstants.THINK_DELAY))
	_phase_tween.tween_callback(_begin_turn_phase_b_chess_move)

# ==============================================================================
# FASE B: MOVIMIENTO FISICO ESTILO PIEZA DE AJEDREZ (CHESS_MOVE_DURATION = 0.85 s)
# ==============================================================================
func _begin_turn_phase_b_chess_move() -> void:
	if not is_step_in_progress:
		return

	# Si hubo ediciones del Modo Dios durante la Fase A de deliberacion, re-evaluamos antes de mover
	if not _pending_god_edits_reasons.is_empty():
		var combined: String = "; ".join(_pending_god_edits_reasons)
		_pending_god_edits_reasons.clear()
		knowledge_engine.handle_god_mode_modification(world_truth, turn_number, combined)
		var replan: Dictionary = knowledge_engine.plan_next_route(turn_number)
		knowledge_engine.emit_epistemic_visual_update()
		if String(replan.get("status", "")) != "HAS_ROUTE":
			is_step_in_progress = false
			turn_phase = TurnPhase.IDLE
			if String(replan.get("status", "")) == "BLOCKED":
				_change_sim_state(
					GameConstants.SimState.WAITING_FOR_GOD_MODE,
					"BLOQUEO SEGURO: %s" % [String(replan.get("reason", "Rutas bloqueadas."))]
				)
			return
		_step_target_cell = replan.get("next_cell", _step_origin_cell) as Vector2i

	# Verificar si la celda destino es un Muro fisico oculto en WorldTruthData
	if world_truth.has_wall(_step_target_cell):
		var bump_dir: Vector2i = _step_target_cell - _step_origin_cell
		if bump_dir != Vector2i.ZERO:
			knowledge_engine.epistemic_map.agent_facing = bump_dir
		knowledge_engine.epistemic_map.mark_wall_state(_step_target_cell, true)
		EventBus.xai_rule_triggered.emit(
			turn_number,
			"BUMP-WALL",
			"Sensores tactiles detectan MURO impasable en %s. Re-calculando ruta." % [str(_step_target_cell)]
		)
		knowledge_engine.rule_engine.run_forward_chaining(
			knowledge_engine.epistemic_map,
			knowledge_engine.nav_planner,
			world_truth,
			turn_number
		)
		knowledge_engine.plan_next_route(turn_number)
		knowledge_engine.emit_epistemic_visual_update()
		EventBus.agent_transform_updated.emit(
			knowledge_engine.epistemic_map.agent_pos,
			knowledge_engine.epistemic_map.agent_facing,
			false
		)
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		if sim_state == GameConstants.SimState.STEPPING:
			_change_sim_state(GameConstants.SimState.PAUSED, "Muro detectado en %s. Paso completado." % [str(_step_target_cell)])
		elif sim_state == GameConstants.SimState.RUNNING:
			_begin_turn_phase_a_deliberation()
		return

	turn_phase = TurnPhase.PHASE_B_MOVING
	var move_dir: Vector2i = _step_target_cell - _step_origin_cell
	if move_dir != Vector2i.ZERO:
		knowledge_engine.epistemic_map.agent_facing = move_dir

	# Dispara la coreografia de 4 sub-etapas estilo pieza de ajedrez en AgentVisual3D
	EventBus.agent_transform_updated.emit(
		_step_target_cell,
		knowledge_engine.epistemic_map.agent_facing,
		true
	)

	_cancel_active_phase_tween()
	_phase_tween = create_tween()
	_phase_tween.tween_interval(_get_scaled_time(GameConstants.CHESS_MOVE_DURATION))
	_phase_tween.tween_callback(_begin_turn_phase_c_settle)

# ==============================================================================
# FASE C: ASENTAMIENTO EN CASILLA (SETTLE_DELAY = 0.35 s base)
# ==============================================================================
func _begin_turn_phase_c_settle() -> void:
	if not is_step_in_progress:
		return

	turn_phase = TurnPhase.PHASE_C_SETTLING
	knowledge_engine.epistemic_map.agent_pos = _step_target_cell

	# Evaluar supervivencia y sensores al posarse la pieza sobre la nueva baldosa
	var arrival_eval: Dictionary = knowledge_engine.perceive_and_reason_at_current_cell(world_truth, turn_number)
	if bool(arrival_eval.get("gold_just_captured", false)) or bool(arrival_eval.get("arrow_shot_performed", false)):
		EventBus.world_truth_changed.emit(world_truth.to_snapshot())

	if not bool(arrival_eval.get("survived", true)):
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		var death_cause: String = "cayo en un Pozo abismal" if bool(arrival_eval.get("killed_by_pit", false)) else "fue devorado por el Wumpus"
		_change_sim_state(
			GameConstants.SimState.GAME_OVER,
			"GAME OVER en %s: El agente %s." % [str(_step_target_cell), death_cause]
		)
		EventBus.xai_rule_triggered.emit(
			turn_number,
			"FATAL",
			"La pieza exploradora %s en la celda %s." % [death_cause, str(_step_target_cell)]
		)
		knowledge_engine.emit_epistemic_visual_update()
		return

	# Procesar ediciones del Modo Dios ocurridas mientras la pieza estaba en el aire (Regla 6)
	if not _pending_god_edits_reasons.is_empty():
		var combined_reasons: String = "; ".join(_pending_god_edits_reasons)
		_pending_god_edits_reasons.clear()
		knowledge_engine.handle_god_mode_modification(world_truth, turn_number, combined_reasons)

	# Verificar victoria inmediata si llego a (0, 0) con el Oro
	if knowledge_engine.epistemic_map.has_gold and knowledge_engine.epistemic_map.agent_pos == Vector2i.ZERO:
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		knowledge_engine.active_path.clear()
		knowledge_engine.emit_epistemic_visual_update()
		_change_sim_state(
			GameConstants.SimState.VICTORY,
			"¡VICTORIA EN TURNO %d! Extraccion completada en (0, 0) con el Lingote de Oro." % [turn_number]
		)
		EventBus.xai_rule_triggered.emit(
			turn_number,
			"VICTORY",
			"Extraccion exitosa en (0, 0). Mision cumplida."
		)
		return

	var next_plan: Dictionary = knowledge_engine.plan_next_route(turn_number)
	knowledge_engine.emit_epistemic_visual_update()

	if String(next_plan.get("status", "")) == "BLOCKED":
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		_change_sim_state(
			GameConstants.SimState.WAITING_FOR_GOD_MODE,
			"BLOQUEO SEGURO: %s" % [String(next_plan.get("reason", "Rutas bloqueadas."))]
		)
		return

	# Pausa de asentamiento (SETTLE_DELAY) tras el aterrizaje de la pieza antes del siguiente turno
	_cancel_active_phase_tween()
	_phase_tween = create_tween()
	_phase_tween.tween_interval(_get_scaled_time(GameConstants.SETTLE_DELAY))
	_phase_tween.tween_callback(_on_phase_c_settle_completed)

func _on_phase_c_settle_completed() -> void:
	is_step_in_progress = false
	turn_phase = TurnPhase.IDLE

	if sim_state == GameConstants.SimState.STEPPING:
		_change_sim_state(
			GameConstants.SimState.PAUSED,
			"Turno %d completado en casilla %s." % [turn_number, str(knowledge_engine.epistemic_map.agent_pos)]
		)
	elif sim_state == GameConstants.SimState.RUNNING:
		_begin_turn_phase_a_deliberation()
