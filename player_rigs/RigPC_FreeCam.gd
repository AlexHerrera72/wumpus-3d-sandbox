class_name RigPC_FreeCam
extends Node3D
## Sistema Multi-Camara: RigPC_FreeCam (Modo 1 - Escritorio PC)
## - Click Izquierdo: coloca/alterna la herramienta activa.
## - Click Derecho rapido: borra/quita cualquier objeto de la casilla sin cambiar herramienta.
## - Click Derecho mantenido + mover raton / WASD/QE/Shift: vuelo libre 3D.
## - Seguimiento automatico del agente al dar Play (RUNNING).

const BASE_FLY_SPEED: float = 8.5
const FAST_SPEED_MULTIPLIER: float = 2.0
const MOUSE_SENSITIVITY: float = 0.0028
const MAX_PITCH_RAD: float = deg_to_rad(85.0)
const FOLLOW_OFFSET: Vector3 = Vector3(-2.6, 8.4, 7.6)

var camera: Camera3D
var is_active_rig: bool = false
var is_flying: bool = false

var _yaw: float = -0.42
var _pitch: float = -0.68
var _grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var _active_tool: GameConstants.GodTool = GameConstants.GodTool.TOGGLE_PIT
var _hovered_cell: Vector2i = Vector2i.ZERO
var _is_hover_valid: bool = false

# Seguimiento automatico al personaje en modo PLAY
var _follow_agent: bool = false
var _agent_grid_pos: Vector3i = Vector3i.ZERO

# Diferenciacion entre Click Derecho rapido (Borrar) y Click Derecho arrastrado (Volar)
var _rmb_down: bool = false
var _rmb_drag_dist: float = 0.0
var _rmb_press_ms: int = 0

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "PCFreeCamera3D"
	camera.fov = 60.0
	add_child(camera)

	_reset_camera_pose()

	EventBus.god_tool_changed.connect(_on_god_tool_changed)
	EventBus.world_truth_changed.connect(_on_world_truth_changed)
	EventBus.sim_state_changed.connect(_on_sim_state_changed)
	EventBus.agent_transform_3d_updated.connect(_on_agent_transform_3d_updated)
	EventBus.agent_teleported.connect(_on_agent_teleported)

func set_rig_active(active: bool) -> void:
	is_active_rig = active
	visible = active
	if camera != null:
		camera.current = active
	if not active and is_flying:
		_stop_flying()

func _stop_flying() -> void:
	is_flying = false
	_rmb_down = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _reset_camera_pose() -> void:
	var center_x: float = float(_grid_size.x - 1) * GameConstants.CELL_SIZE * 0.5
	var center_z: float = float(_grid_size.y - 1) * GameConstants.CELL_SIZE * 0.5
	position = Vector3(center_x - 4.5, 9.5, center_z + 10.5)
	_yaw = -0.42
	_pitch = -0.68
	_apply_rotation()

func _apply_rotation() -> void:
	rotation = Vector3.ZERO
	if camera != null:
		camera.rotation = Vector3(_pitch, _yaw, 0.0)

func _on_god_tool_changed(new_tool: GameConstants.GodTool) -> void:
	_active_tool = new_tool

func _on_world_truth_changed(truth_snapshot: Dictionary) -> void:
	var new_size: Vector2i = truth_snapshot.get("grid_size", GameConstants.DEFAULT_GRID_SIZE) as Vector2i
	if new_size != _grid_size:
		_grid_size = new_size

func _on_sim_state_changed(new_state: GameConstants.SimState, _msg: String) -> void:
	_follow_agent = (new_state == GameConstants.SimState.RUNNING)

func _on_agent_transform_3d_updated(grid_pos: Vector3i, _facing_dir: Vector2i, _is_moving: bool) -> void:
	_agent_grid_pos = grid_pos

func _on_agent_teleported(_from_cell: Vector3i, to_cell: Vector3i) -> void:
	_agent_grid_pos = to_cell

func _process(delta: float) -> void:
	if not is_active_rig or camera == null:
		return
	if not GameConstants.is_gameplay_active:
		if is_flying or _rmb_down:
			_stop_flying()
		return

	# Si mantiene Click Derecho presionado mas de 220 ms, pasa a modo vuelo libre
	if _rmb_down and not is_flying:
		if Time.get_ticks_msec() - _rmb_press_ms > 220:
			is_flying = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if is_flying:
		_process_free_flight(delta)
	else:
		if _follow_agent:
			_process_agent_follow(delta)
		_update_board_raycast()

func _process_agent_follow(delta: float) -> void:
	var agent_local: Vector3 = GameConstants.grid3_to_world(_agent_grid_pos, 0.5)
	var agent_world: Vector3 = GameConstants.board_global_transform * agent_local
	var desired_pos: Vector3 = agent_world + FOLLOW_OFFSET

	var t: float = clampf(delta * 4.5, 0.0, 1.0)
	global_position = global_position.lerp(desired_pos, t)

	var look_vec: Vector3 = (agent_world - global_position).normalized()
	if look_vec.length_squared() > 0.001:
		var target_yaw: float = atan2(-look_vec.x, -look_vec.z)
		var horiz_len: float = sqrt(look_vec.x * look_vec.x + look_vec.z * look_vec.z)
		var target_pitch: float = clampf(atan2(look_vec.y, maxf(horiz_len, 0.001)), -MAX_PITCH_RAD, MAX_PITCH_RAD)
		_yaw = lerp_angle(_yaw, target_yaw, t)
		_pitch = lerpf(_pitch, target_pitch, t)
		_apply_rotation()

func _process_free_flight(delta: float) -> void:
	var move_input: Vector3 = Vector3.ZERO
	var cam_basis: Basis = camera.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	var right: Vector3 = cam_basis.x

	if Input.is_key_pressed(KEY_W):
		move_input += forward
	if Input.is_key_pressed(KEY_S):
		move_input -= forward
	if Input.is_key_pressed(KEY_D):
		move_input += right
	if Input.is_key_pressed(KEY_A):
		move_input -= right
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		move_input += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		move_input += Vector3.DOWN

	if move_input.length_squared() > 0.001:
		move_input = move_input.normalized()
		var speed: float = BASE_FLY_SPEED
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= FAST_SPEED_MULTIPLIER
		global_position += move_input * speed * delta
		global_position.y = clampf(global_position.y, 1.2, 32.0)

func _update_board_raycast() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var mouse_pos: Vector2 = viewport.get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = camera.project_ray_normal(mouse_pos)

	var cell: Vector2i = GameConstants.world_ray_to_grid(ray_origin, ray_normal, _grid_size)
	var valid: bool = (cell != Vector2i(-1, -1))

	if cell != _hovered_cell or valid != _is_hover_valid:
		_hovered_cell = cell
		_is_hover_valid = valid
		EventBus.cursor_cell_hovered.emit(_hovered_cell, _is_hover_valid)

func _cycle_tool(offset: int) -> void:
	var count: int = GameConstants.get_tool_count()
	var next_idx: int = posmod(int(_active_tool) + offset, count)
	EventBus.god_tool_changed.emit(next_idx as GameConstants.GodTool)

func _unhandled_input(event: InputEvent) -> void:
	if not is_active_rig or not GameConstants.is_gameplay_active:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				is_flying = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				_stop_flying()
			get_viewport().set_input_as_handled()
			return

		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rmb_down = true
				_rmb_drag_dist = 0.0
				_rmb_press_ms = Time.get_ticks_msec()
			else:
				var was_quick_click: bool = _rmb_down and (not is_flying) and (_rmb_drag_dist < 8.0)
				_stop_flying()
				if was_quick_click:
					# Click Derecho rapido: quitar/borrar cualquier objeto de la casilla directamente!
					_update_board_raycast()
					if _is_hover_valid:
						EventBus.god_action_requested.emit(_hovered_cell, GameConstants.GodTool.CLEAR_CELL)
			get_viewport().set_input_as_handled()
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not is_flying:
			_update_board_raycast()
			if _is_hover_valid:
				EventBus.god_action_requested.emit(_hovered_cell, _active_tool)
				get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if _rmb_down and not is_flying:
			_rmb_drag_dist += mm.relative.length()
			if _rmb_drag_dist >= 8.0:
				is_flying = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if is_flying:
			_yaw -= mm.relative.x * MOUSE_SENSITIVITY
			_pitch = clampf(_pitch - mm.relative.y * MOUSE_SENSITIVITY, -MAX_PITCH_RAD, MAX_PITCH_RAD)
			_apply_rotation()
			get_viewport().set_input_as_handled()
			return

	if is_flying:
		return

	if event.is_action_pressed("action_primary", false, true):
		EventBus.sim_control_requested.emit("TOGGLE_PAUSE")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("action_back", false, true):
		EventBus.sim_control_requested.emit("RESET")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("action_menu", false, true):
		EventBus.menu_drawer_toggled.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("action_aux", false, true):
		_cycle_tool(1)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		match ke.keycode:
			KEY_1:
				EventBus.god_tool_changed.emit(GameConstants.GodTool.TOGGLE_PIT)
			KEY_2:
				EventBus.god_tool_changed.emit(GameConstants.GodTool.TOGGLE_WUMPUS)
			KEY_3:
				EventBus.god_tool_changed.emit(GameConstants.GodTool.TOGGLE_WALL)
			KEY_4:
				EventBus.god_tool_changed.emit(GameConstants.GodTool.MOVE_GOLD)
			KEY_5:
				EventBus.god_tool_changed.emit(GameConstants.GodTool.TOGGLE_PORTAL)
			KEY_6:
				EventBus.god_tool_changed.emit(GameConstants.GodTool.TOGGLE_STAIRS)
			KEY_7:
				EventBus.god_tool_changed.emit(GameConstants.GodTool.TOGGLE_ARROW)
			KEY_8:
				EventBus.god_tool_changed.emit(GameConstants.GodTool.CLEAR_CELL)
			KEY_N:
				EventBus.sim_control_requested.emit("STEP")
				get_viewport().set_input_as_handled()
