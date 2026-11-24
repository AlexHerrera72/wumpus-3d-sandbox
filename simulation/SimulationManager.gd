class_name SimulationManager
extends Node
## Controlador de Simulacion: SimulationManager
## Gestiona el ciclo de turnos discretos en 3 fases estilo Ajedrez, mazmorras de
## hasta 5 pisos, Escaleras entre pisos, multiples pares de Portales Azul/Naranja
## con validacion, multiples Wumpus, Flechas recogibles y guardado/carga JSON.

const MAPS_DIR: String = "user://maps"

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
var _step_origin_cell: Vector3i = Vector3i.ZERO
var _step_target_cell: Vector3i = Vector3i.ZERO
var _pending_god_edits_reasons: Array[String] = []
var _was_running_before_wait: bool = false

var _phase_tween: Tween

func _ready() -> void:
	world_truth = WorldTruthData.new(GameConstants.DEFAULT_GRID_SIZE)
	knowledge_engine = KnowledgeEngine.new(GameConstants.DEFAULT_GRID_SIZE, 1)

	EventBus.god_action_requested.connect(_on_god_action_requested)
	EventBus.sim_control_requested.connect(_on_sim_control_requested)
	EventBus.board_resize_requested.connect(_on_board_resize_requested)
	EventBus.sim_speed_changed.connect(_on_sim_speed_changed)
	EventBus.floor_add_requested.connect(_on_floor_add_requested)
	EventBus.floor_remove_requested.connect(_on_floor_remove_requested)
	EventBus.active_floor_switch_requested.connect(_on_active_floor_switch_requested)
	EventBus.active_floor_step_requested.connect(_on_active_floor_step_requested)
	EventBus.map_save_requested.connect(_on_map_save_requested)
	EventBus.map_load_requested.connect(_on_map_load_requested)
	EventBus.map_delete_requested.connect(_on_map_delete_requested)
	EventBus.map_reset_default_requested.connect(_on_map_reset_default_requested)

	call_deferred("_boot_initial_simulation")

func _boot_initial_simulation() -> void:
	_migrate_legacy_maps_into_fixed_user_dir()
	_restore_default_map(GameConstants.DEFAULT_GRID_SIZE, 1)
	_broadcast_saved_maps_list("")

func _migrate_legacy_maps_into_fixed_user_dir() -> void:
	## Migra automaticamente mapas guardados en carpetas anteriores de Godot
	## (cuando cambio el nombre del proyecto) hacia la carpeta fija user://maps/.
	_ensure_maps_dir()
	var data_root: String = OS.get_data_dir()
	var legacy_roots: Array[String] = [
		data_root.path_join("godot").path_join("app_userdata"),
		data_root.path_join("Godot").path_join("app_userdata")
	]
	var legacy_folder_names: Array[String] = [
		"Mundo de Wumpus Autonomo 3D Sandbox",
		"La maravillosa aventura del Amongus asesino de Wumpus"
	]

	for app_userdata_root: String in legacy_roots:
		for folder_name: String in legacy_folder_names:
			var legacy_maps_path: String = app_userdata_root.path_join(folder_name).path_join("maps")
			if not DirAccess.dir_exists_absolute(legacy_maps_path):
				continue
			var dir: DirAccess = DirAccess.open(legacy_maps_path)
			if dir == null:
				continue
			dir.list_dir_begin()
			var fname: String = dir.get_next()
			while not fname.is_empty():
				if not dir.current_is_dir() and fname.ends_with(".json"):
					var src_path: String = legacy_maps_path.path_join(fname)
					var dst_path: String = "%s/%s" % [MAPS_DIR, fname]
					if not FileAccess.file_exists(dst_path):
						var f_in: FileAccess = FileAccess.open(src_path, FileAccess.READ)
						if f_in != null:
							var content: String = f_in.get_as_text()
							f_in.close()
							var f_out: FileAccess = FileAccess.open(dst_path, FileAccess.WRITE)
							if f_out != null:
								f_out.store_string(content)
								f_out.close()
				fname = dir.get_next()
			dir.list_dir_end()

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

func _restore_default_map(target_size: Vector2i, target_floors: int) -> void:
	world_truth.setup_default_scenario(target_size, target_floors)
	_set_active_view_floor(0)
	_restart_preserving_current_map("Mapa por defecto %dx%d (%d piso%s) cargado." % [
		world_truth.grid_size.x,
		world_truth.grid_size.y,
		world_truth.floor_count,
		"s" if world_truth.floor_count > 1 else ""
	])

func _restart_preserving_current_map(status_msg: String = "") -> void:
	_cancel_active_phase_tween()
	is_step_in_progress = false
	turn_phase = TurnPhase.IDLE
	_pending_god_edits_reasons.clear()
	turn_number = 0
	_was_running_before_wait = false

	world_truth.reset_run_preserve_map()
	GameConstants.active_floor_count = world_truth.floor_count
	if GameConstants.active_view_floor >= world_truth.floor_count:
		GameConstants.active_view_floor = 0

	knowledge_engine.reset_knowledge(world_truth.grid_size, world_truth.floor_count)
	knowledge_engine.perceive_and_reason_at_current_cell(world_truth, turn_number)
	knowledge_engine.plan_next_route(turn_number, world_truth)

	EventBus.world_truth_changed.emit(world_truth.to_snapshot())
	EventBus.active_floor_changed.emit(GameConstants.active_view_floor, world_truth.floor_count)
	knowledge_engine.emit_epistemic_visual_update()
	_emit_agent_transform(knowledge_engine.epistemic_map.agent_pos, knowledge_engine.epistemic_map.agent_facing, false)

	var msg: String = status_msg
	if msg.is_empty():
		msg = "Agente reiniciado en (0,0,P1). Tu mapa personalizado se conserva intacto."
	_change_sim_state(GameConstants.SimState.PAUSED, msg)
	EventBus.xai_rule_triggered.emit(0, "INIT", msg)

func _emit_agent_transform(pos3: Vector3i, facing: Vector2i, is_moving: bool) -> void:
	EventBus.agent_transform_3d_updated.emit(pos3, facing, is_moving)
	EventBus.agent_transform_updated.emit(Vector2i(pos3.x, pos3.y), facing, is_moving)

func _cancel_active_phase_tween() -> void:
	if _phase_tween != null and _phase_tween.is_valid():
		_phase_tween.kill()
	_phase_tween = null

func _change_sim_state(new_state: GameConstants.SimState, message: String) -> void:
	sim_state = new_state
	EventBus.sim_state_changed.emit(sim_state, message)

func _on_board_resize_requested(new_size: Vector2i) -> void:
	if new_size == world_truth.grid_size:
		return
	world_truth.resize_preserving_cells(new_size)
	# Si el agente quedo fuera del nuevo limite, reiniciamos su posicion en (0,0,P1) preservando el mapa recortado
	if not world_truth.is_within_bounds(knowledge_engine.epistemic_map.agent_pos):
		_restart_preserving_current_map("Tablero ajustado a %dx%d conservando tus casillas." % [new_size.x, new_size.y])
	else:
		_rebuild_epistemic_after_floor_change("Tablero redimensionado a %dx%d." % [new_size.x, new_size.y])
		_emit_agent_transform(knowledge_engine.epistemic_map.agent_pos, knowledge_engine.epistemic_map.agent_facing, false)
	EventBus.ui_notification_requested.emit("Tablero %dx%d aplicado." % [new_size.x, new_size.y], false)

func _on_map_reset_default_requested() -> void:
	_restore_default_map(world_truth.grid_size, world_truth.floor_count)

func _on_floor_add_requested() -> void:
	var res: Dictionary = world_truth.add_floor()
	var changed: bool = bool(res.get("changed", false))
	var reason: String = String(res.get("reason", ""))
	if not changed:
		EventBus.ui_notification_requested.emit(reason, true)
		EventBus.xai_rule_triggered.emit(turn_number, "FLOOR-MAX", reason)
		return

	_rebuild_epistemic_after_floor_change(reason)
	_set_active_view_floor(world_truth.floor_count - 1)
	EventBus.ui_notification_requested.emit(reason, false)

func _on_floor_remove_requested() -> void:
	var res: Dictionary = world_truth.remove_top_floor()
	var changed: bool = bool(res.get("changed", false))
	var reason: String = String(res.get("reason", ""))
	if not changed:
		EventBus.ui_notification_requested.emit(reason, true)
		return

	if GameConstants.active_view_floor >= world_truth.floor_count:
		GameConstants.active_view_floor = world_truth.floor_count - 1

	if knowledge_engine.epistemic_map.agent_pos.z >= world_truth.floor_count:
		_restart_preserving_current_map(reason)
	else:
		_rebuild_epistemic_after_floor_change(reason)
	EventBus.ui_notification_requested.emit(reason, false)

func _rebuild_epistemic_after_floor_change(reason: String) -> void:
	GameConstants.active_floor_count = world_truth.floor_count
	var prev_agent_pos: Vector3i = knowledge_engine.epistemic_map.agent_pos
	var prev_facing: Vector2i = knowledge_engine.epistemic_map.agent_facing
	var prev_visited: Array[Vector3i] = knowledge_engine.epistemic_map.visited_cells.duplicate()
	var prev_has_gold: bool = knowledge_engine.epistemic_map.has_gold
	var prev_arrows: int = knowledge_engine.epistemic_map.arrow_count

	knowledge_engine.reset_knowledge(world_truth.grid_size, world_truth.floor_count)
	knowledge_engine.epistemic_map.agent_pos = prev_agent_pos
	knowledge_engine.epistemic_map.agent_facing = prev_facing
	knowledge_engine.epistemic_map.has_gold = prev_has_gold
	knowledge_engine.epistemic_map.arrow_count = prev_arrows
	for vp: Vector3i in prev_visited:
		if knowledge_engine.epistemic_map.is_within_bounds(vp):
			var p: Dictionary = world_truth.sample_percepts_at(vp)
			knowledge_engine.epistemic_map.register_visited_percepts(vp, p)

	knowledge_engine.handle_god_mode_modification(world_truth, turn_number, reason)
	EventBus.world_truth_changed.emit(world_truth.to_snapshot())
	EventBus.active_floor_changed.emit(GameConstants.active_view_floor, world_truth.floor_count)
	knowledge_engine.emit_epistemic_visual_update()

func _set_active_view_floor(target_floor: int) -> void:
	var clamped: int = clampi(target_floor, 0, world_truth.floor_count - 1)
	GameConstants.active_view_floor = clamped
	GameConstants.active_floor_count = world_truth.floor_count
	EventBus.active_floor_changed.emit(GameConstants.active_view_floor, world_truth.floor_count)
	knowledge_engine.emit_epistemic_visual_update()

func _on_active_floor_switch_requested(target_floor: int) -> void:
	if world_truth.floor_count < 2:
		return
	var next_floor: int = target_floor
	if next_floor < 0:
		next_floor = (GameConstants.active_view_floor + 1) % world_truth.floor_count
	_set_active_view_floor(next_floor)

func _on_active_floor_step_requested(delta_floor: int) -> void:
	if world_truth.floor_count < 2:
		return
	var target: int = clampi(GameConstants.active_view_floor + delta_floor, 0, world_truth.floor_count - 1)
	if target != GameConstants.active_view_floor:
		_set_active_view_floor(target)

func _validate_ready_to_run() -> bool:
	if not world_truth.has_gold_placed() and not knowledge_engine.epistemic_map.has_gold:
		var msg_gold: String = "Advertencia: Debes colocar el Oro en el mapa antes de iniciar."
		EventBus.ui_notification_requested.emit(msg_gold, true)
		EventBus.xai_rule_triggered.emit(turn_number, "VAL-ORO", msg_gold)
		return false
	if world_truth.has_unlinked_portal():
		var p: Vector3i = world_truth.pending_blue_portal
		var msg_p: String = "Validacion: Portal AZUL sin pareja NARANJA en (%d,%d,P%d)." % [p.x, p.y, p.z + 1]
		EventBus.ui_notification_requested.emit(msg_p, true)
		EventBus.xai_rule_triggered.emit(turn_number, "VAL-PORTAL", msg_p)
		return false
	if world_truth.has_unlinked_stairs():
		var s: Vector3i = world_truth.pending_stairs
		var msg_s: String = "Validacion: Escalera incompleta en (%d,%d,P%d). Conecta otro piso o eliminala." % [s.x, s.y, s.z + 1]
		EventBus.ui_notification_requested.emit(msg_s, true)
		EventBus.xai_rule_triggered.emit(turn_number, "VAL-ESCALERA", msg_s)
		return false
	return true

func _on_sim_control_requested(action: String) -> void:
	match action.to_upper():
		"PLAY":
			if not _validate_ready_to_run():
				return
			if sim_state in [GameConstants.SimState.VICTORY, GameConstants.SimState.GAME_OVER]:
				_restart_preserving_current_map("Nueva ejecucion sobre tu mapa actual.")
			# Enfocar automaticamente el piso donde esta el personaje para seguirlo
			if knowledge_engine.epistemic_map.agent_pos.z != GameConstants.active_view_floor:
				_set_active_view_floor(knowledge_engine.epistemic_map.agent_pos.z)
			_emit_agent_transform(knowledge_engine.epistemic_map.agent_pos, knowledge_engine.epistemic_map.agent_facing, false)
			_was_running_before_wait = true
			_change_sim_state(GameConstants.SimState.RUNNING, "Ejecutando (%.1fx)." % [speed_multiplier])
			if not is_step_in_progress:
				_begin_turn_phase_a_deliberation()

		"PAUSE":
			_was_running_before_wait = false
			_change_sim_state(GameConstants.SimState.PAUSED, "En pausa.")

		"TOGGLE_PAUSE":
			if sim_state == GameConstants.SimState.RUNNING:
				_on_sim_control_requested("PAUSE")
			else:
				_on_sim_control_requested("PLAY")

		"STEP":
			if not _validate_ready_to_run():
				return
			if sim_state in [GameConstants.SimState.VICTORY, GameConstants.SimState.GAME_OVER]:
				return
			if knowledge_engine.epistemic_map.agent_pos.z != GameConstants.active_view_floor:
				_set_active_view_floor(knowledge_engine.epistemic_map.agent_pos.z)
			_was_running_before_wait = false
			_change_sim_state(GameConstants.SimState.STEPPING, "1 paso...")
			if not is_step_in_progress:
				_begin_turn_phase_a_deliberation()

		"RESET":
			_restart_preserving_current_map("Reiniciado conservando tu mapa.")

func _on_god_action_requested(cell_2d: Vector2i, tool: GameConstants.GodTool) -> void:
	var cell: Vector3i = Vector3i(cell_2d.x, cell_2d.y, GameConstants.active_view_floor)
	var agent_pos: Vector3i = knowledge_engine.epistemic_map.agent_pos
	var edit_result: Dictionary = world_truth.apply_god_tool(cell, tool, agent_pos)
	var changed: bool = bool(edit_result.get("changed", false))
	var reason: String = String(edit_result.get("reason", ""))

	if not changed:
		if not reason.is_empty():
			EventBus.xai_rule_triggered.emit(turn_number, "VALIDACION", reason)
			EventBus.ui_notification_requested.emit(reason, true)
		return

	if tool in [GameConstants.GodTool.TOGGLE_PORTAL, GameConstants.GodTool.TOGGLE_STAIRS, GameConstants.GodTool.MOVE_GOLD]:
		EventBus.ui_notification_requested.emit(reason, false)

	EventBus.world_truth_changed.emit(world_truth.to_snapshot())

	if is_step_in_progress:
		if cell == _step_target_cell and world_truth.has_wall(cell):
			_cancel_active_phase_tween()
			is_step_in_progress = false
			turn_phase = TurnPhase.IDLE
			knowledge_engine.epistemic_map.agent_pos = _step_origin_cell
			knowledge_engine.epistemic_map.mark_wall_state(cell, true)
			_emit_agent_transform(_step_origin_cell, knowledge_engine.epistemic_map.agent_facing, false)
			knowledge_engine.handle_god_mode_modification(
				world_truth,
				turn_number,
				reason + " (Paso cancelado por nuevo Muro)"
			)
			knowledge_engine.emit_epistemic_visual_update()
			if sim_state == GameConstants.SimState.RUNNING:
				_begin_turn_phase_a_deliberation()
			elif sim_state == GameConstants.SimState.STEPPING:
				_change_sim_state(GameConstants.SimState.PAUSED, "Movimiento cancelado por Muro.")
			return
		else:
			_pending_god_edits_reasons.append(reason)
			return

	knowledge_engine.handle_god_mode_modification(world_truth, turn_number, reason)
	knowledge_engine.emit_epistemic_visual_update()

	if sim_state == GameConstants.SimState.WAITING_FOR_GOD_MODE:
		var plan_check: Dictionary = knowledge_engine.plan_next_route(turn_number, world_truth)
		knowledge_engine.emit_epistemic_visual_update()
		if String(plan_check.get("status", "")) == "HAS_ROUTE":
			if _was_running_before_wait:
				_change_sim_state(GameConstants.SimState.RUNNING, "Camino desbloqueado. Reanudando partida.")
				_begin_turn_phase_a_deliberation()
			else:
				_change_sim_state(GameConstants.SimState.PAUSED, "Camino desbloqueado por Modo Dios.")

# ==============================================================================
# PERSISTENCIA DE MAPAS (user://maps/*.json)
# ==============================================================================
func _ensure_maps_dir() -> void:
	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		DirAccess.make_dir_recursive_absolute(MAPS_DIR)

func _sanitize_map_name(raw_name: String) -> String:
	var cleaned: String = raw_name.strip_edges()
	var invalid_chars: PackedStringArray = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "."]
	for ch: String in invalid_chars:
		cleaned = cleaned.replace(ch, "_")
	if cleaned.is_empty():
		cleaned = "mapa_%d" % [Time.get_unix_time_from_system()]
	return cleaned

func _list_saved_map_names() -> Array[String]:
	_ensure_maps_dir()
	var result: Array[String] = []
	var dir: DirAccess = DirAccess.open(MAPS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and fname.ends_with(".json"):
			result.append(fname.get_basename())
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result

func _broadcast_saved_maps_list(status_msg: String) -> void:
	EventBus.saved_maps_list_updated.emit(_list_saved_map_names(), status_msg)

func _on_map_save_requested(map_name: String) -> void:
	if world_truth.has_unlinked_portal():
		var msg: String = "No puedes guardar: hay un Portal AZUL sin pareja NARANJA."
		EventBus.ui_notification_requested.emit(msg, true)
		_broadcast_saved_maps_list(msg)
		return
	if world_truth.has_unlinked_stairs():
		var msg_s: String = "No puedes guardar: hay una Escalera sin conectar a otro piso."
		EventBus.ui_notification_requested.emit(msg_s, true)
		_broadcast_saved_maps_list(msg_s)
		return
	_ensure_maps_dir()
	var safe_name: String = _sanitize_map_name(map_name)
	var file_path: String = "%s/%s.json" % [MAPS_DIR, safe_name]
	var f: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		_broadcast_saved_maps_list("Error al guardar '%s'." % [safe_name])
		return
	var json_str: String = JSON.stringify(world_truth.serialize_to_dict(), "\t")
	f.store_string(json_str)
	f.close()
	EventBus.xai_rule_triggered.emit(turn_number, "MAP-SAVE", "Mapa guardado como '%s'." % [safe_name])
	_broadcast_saved_maps_list("Mapa '%s' guardado." % [safe_name])

func _on_map_load_requested(map_name: String) -> void:
	var file_path: String = "%s/%s.json" % [MAPS_DIR, map_name]
	if not FileAccess.file_exists(file_path):
		_broadcast_saved_maps_list("No existe el mapa '%s'." % [map_name])
		return
	var f: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		_broadcast_saved_maps_list("Error al abrir '%s'." % [map_name])
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_broadcast_saved_maps_list("Formato JSON invalido en '%s'." % [map_name])
		return
	if world_truth.deserialize_from_dict(parsed as Dictionary):
		_set_active_view_floor(0)
		_restart_preserving_current_map("Mapa '%s' (%d pisos) cargado." % [map_name, world_truth.floor_count])
		_broadcast_saved_maps_list("Cargado: '%s'." % [map_name])
	else:
		_broadcast_saved_maps_list("No se pudo interpretar el mapa '%s'." % [map_name])

func _on_map_delete_requested(map_name: String) -> void:
	var file_path: String = "%s/%s.json" % [MAPS_DIR, map_name]
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
		_broadcast_saved_maps_list("Mapa '%s' eliminado." % [map_name])
	else:
		_broadcast_saved_maps_list("Mapa no encontrado.")

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

	var step_eval: Dictionary = knowledge_engine.perceive_and_reason_at_current_cell(world_truth, turn_number)
	if bool(step_eval.get("arrow_shot_performed", false)) or bool(step_eval.get("arrow_picked", false)) or bool(step_eval.get("gold_just_captured", false)):
		EventBus.world_truth_changed.emit(world_truth.to_snapshot())

	var plan: Dictionary = knowledge_engine.plan_next_route(turn_number, world_truth)
	knowledge_engine.emit_epistemic_visual_update()

	var status: String = String(plan.get("status", "BLOCKED"))
	if status == "AT_EXTRACTION_WITH_GOLD":
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		_change_sim_state(
			GameConstants.SimState.VICTORY,
			"¡VICTORIA EN TURNO %d! Oro extraido en (0,0,P1)." % [turn_number]
		)
		EventBus.xai_rule_triggered.emit(turn_number, "VICTORY", "Mision completada con el Lingote de Oro.")
		return

	if status == "BLOCKED":
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		_change_sim_state(
			GameConstants.SimState.WAITING_FOR_GOD_MODE,
			"BLOQUEO: %s" % [String(plan.get("reason", "Rutas bloqueadas."))]
		)
		EventBus.xai_rule_triggered.emit(turn_number, "WAIT-GOD", "Reloj pausado esperando Modo Dios.")
		return

	_step_origin_cell = knowledge_engine.epistemic_map.agent_pos
	_step_target_cell = plan.get("next_cell", _step_origin_cell) as Vector3i

	_cancel_active_phase_tween()
	_phase_tween = create_tween()
	_phase_tween.tween_interval(_get_scaled_time(GameConstants.THINK_DELAY))
	_phase_tween.tween_callback(_begin_turn_phase_b_chess_move)

# ==============================================================================
# FASE B: MOVIMIENTO DE PIEZA DE AJEDREZ, PORTAL O ESCALERA
# ==============================================================================
func _begin_turn_phase_b_chess_move() -> void:
	if not is_step_in_progress:
		return

	if not _pending_god_edits_reasons.is_empty():
		var combined: String = "; ".join(_pending_god_edits_reasons)
		_pending_god_edits_reasons.clear()
		knowledge_engine.handle_god_mode_modification(world_truth, turn_number, combined)
		var replan: Dictionary = knowledge_engine.plan_next_route(turn_number, world_truth)
		knowledge_engine.emit_epistemic_visual_update()
		if String(replan.get("status", "")) != "HAS_ROUTE":
			is_step_in_progress = false
			turn_phase = TurnPhase.IDLE
			if String(replan.get("status", "")) == "BLOCKED":
				_change_sim_state(GameConstants.SimState.WAITING_FOR_GOD_MODE, "BLOQUEO: Rutas bloqueadas.")
			return
		_step_target_cell = replan.get("next_cell", _step_origin_cell) as Vector3i

	if world_truth.has_wall(_step_target_cell):
		var bump_dir: Vector2i = Vector2i(_step_target_cell.x - _step_origin_cell.x, _step_target_cell.y - _step_origin_cell.y)
		if bump_dir != Vector2i.ZERO:
			knowledge_engine.epistemic_map.agent_facing = bump_dir
		knowledge_engine.epistemic_map.mark_wall_state(_step_target_cell, true)
		EventBus.xai_rule_triggered.emit(
			turn_number,
			"BUMP-WALL",
			"Muro detectado en (%d,%d,P%d). Recalculando ruta." % [_step_target_cell.x, _step_target_cell.y, _step_target_cell.z + 1]
		)
		knowledge_engine.rule_engine.run_forward_chaining(
			knowledge_engine.epistemic_map,
			knowledge_engine.nav_planner,
			world_truth,
			turn_number
		)
		knowledge_engine.plan_next_route(turn_number, world_truth)
		knowledge_engine.emit_epistemic_visual_update()
		_emit_agent_transform(knowledge_engine.epistemic_map.agent_pos, knowledge_engine.epistemic_map.agent_facing, false)
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		if sim_state == GameConstants.SimState.STEPPING:
			_change_sim_state(GameConstants.SimState.PAUSED, "Muro detectado. Paso completado.")
		elif sim_state == GameConstants.SimState.RUNNING:
			_begin_turn_phase_a_deliberation()
		return

	turn_phase = TurnPhase.PHASE_B_MOVING

	var special_dests: Array[Vector3i] = world_truth.get_all_special_destinations(_step_origin_cell)
	var is_special_jump: bool = special_dests.has(_step_target_cell)

	if is_special_jump:
		var is_stair_move: bool = (_step_origin_cell.z != _step_target_cell.z)
		var tag: String = "ESCALERA" if is_stair_move else "PORTAL"
		var verb: String = "Escalera" if is_stair_move else "Portal Azul/Naranja"
		EventBus.xai_rule_triggered.emit(
			turn_number,
			tag,
			"%s: (%d,%d,P%d) -> (%d,%d,P%d)." % [
				verb,
				_step_origin_cell.x, _step_origin_cell.y, _step_origin_cell.z + 1,
				_step_target_cell.x, _step_target_cell.y, _step_target_cell.z + 1
			]
		)
		EventBus.agent_teleported.emit(_step_origin_cell, _step_target_cell)
		if _step_target_cell.z != GameConstants.active_view_floor:
			_set_active_view_floor(_step_target_cell.z)
	else:
		var move_dir: Vector2i = Vector2i(_step_target_cell.x - _step_origin_cell.x, _step_target_cell.y - _step_origin_cell.y)
		if move_dir != Vector2i.ZERO:
			knowledge_engine.epistemic_map.agent_facing = move_dir
		_emit_agent_transform(_step_target_cell, knowledge_engine.epistemic_map.agent_facing, true)

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

	var arrival_eval: Dictionary = knowledge_engine.perceive_and_reason_at_current_cell(world_truth, turn_number)
	if bool(arrival_eval.get("gold_just_captured", false)) or bool(arrival_eval.get("arrow_shot_performed", false)) or bool(arrival_eval.get("arrow_picked", false)):
		EventBus.world_truth_changed.emit(world_truth.to_snapshot())

	if not bool(arrival_eval.get("survived", true)):
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		var death_cause: String = "cayo en un Pozo" if bool(arrival_eval.get("killed_by_pit", false)) else "fue devorado por un Wumpus"
		_change_sim_state(
			GameConstants.SimState.GAME_OVER,
			"GAME OVER en (%d,%d,P%d): El agente %s." % [_step_target_cell.x, _step_target_cell.y, _step_target_cell.z + 1, death_cause]
		)
		EventBus.xai_rule_triggered.emit(turn_number, "FATAL", "Agente eliminado: %s." % [death_cause])
		knowledge_engine.emit_epistemic_visual_update()
		return

	if not _pending_god_edits_reasons.is_empty():
		var combined_reasons: String = "; ".join(_pending_god_edits_reasons)
		_pending_god_edits_reasons.clear()
		knowledge_engine.handle_god_mode_modification(world_truth, turn_number, combined_reasons)

	if knowledge_engine.epistemic_map.has_gold and knowledge_engine.epistemic_map.agent_pos == Vector3i(0, 0, 0):
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		knowledge_engine.active_path.clear()
		knowledge_engine.emit_epistemic_visual_update()
		_change_sim_state(
			GameConstants.SimState.VICTORY,
			"¡VICTORIA EN TURNO %d! Extraccion completada en (0,0,P1)." % [turn_number]
		)
		EventBus.xai_rule_triggered.emit(turn_number, "VICTORY", "Extraccion exitosa con el Lingote de Oro.")
		return

	var next_plan: Dictionary = knowledge_engine.plan_next_route(turn_number, world_truth)
	knowledge_engine.emit_epistemic_visual_update()

	if String(next_plan.get("status", "")) == "BLOCKED":
		is_step_in_progress = false
		turn_phase = TurnPhase.IDLE
		_change_sim_state(GameConstants.SimState.WAITING_FOR_GOD_MODE, "BLOQUEO: Rutas bloqueadas.")
		return

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
			"Turno %d completado en (%d,%d,P%d)." % [
				turn_number,
				knowledge_engine.epistemic_map.agent_pos.x,
				knowledge_engine.epistemic_map.agent_pos.y,
				knowledge_engine.epistemic_map.agent_pos.z + 1
			]
		)
	elif sim_state == GameConstants.SimState.RUNNING:
		_begin_turn_phase_a_deliberation()
