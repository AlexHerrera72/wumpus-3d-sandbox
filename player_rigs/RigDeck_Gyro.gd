class_name RigDeck_Gyro
extends Node3D
## Sistema Multi-Camara: RigDeck_Gyro (Modo 2 - Steam Deck / Gamepad / Tactil)
## Implementa camara orbital centrada en el tablero, lectura nativa de giroscopio
## (Input.get_gyroscope()), esquema unificado de 4 botones (A=Play/Pausa, B=Stop,
## Y=Menu Desplegable, X=Ciclar Herramienta), gatillo R2/Tactil para colocar
## piezas y raycast en el espacio local del piso activo.

var camera_pivot: Node3D
var camera: Camera3D

var is_active_rig: bool = false
var gyro_enabled: bool = true

var _grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var _active_tool: GameConstants.GodTool = GameConstants.GodTool.TOGGLE_PIT
var _cursor_cell: Vector2i = Vector2i(1, 1)
var _continuous_pointer_xz: Vector2 = Vector2(2.0, 2.0)

var _base_orbital_yaw: float = 0.0
var _base_orbital_pitch: float = -0.78
var _gyro_yaw_offset: float = 0.0
var _gyro_pitch_offset: float = 0.0
var _orbital_distance: float = 13.5
var _stick_move_cooldown: float = 0.0
var _r2_was_pressed: bool = false
var _follow_agent: bool = false
var _agent_grid_pos: Vector3i = Vector3i.ZERO

func _ready() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot3D"
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "DeckOrbitalCamera3D"
	camera.fov = 58.0
	camera_pivot.add_child(camera)

	_recenter_pivot()
	_apply_orbital_transform()

	EventBus.god_tool_changed.connect(_on_god_tool_changed)
	EventBus.world_truth_changed.connect(_on_world_truth_changed)
	EventBus.sim_state_changed.connect(func(st: GameConstants.SimState, _m: String) -> void: _follow_agent = (st == GameConstants.SimState.RUNNING))
	EventBus.agent_transform_3d_updated.connect(func(p: Vector3i, _f: Vector2i, _mv: bool) -> void: _agent_grid_pos = p)
	EventBus.agent_teleported.connect(func(_fr: Vector3i, to_c: Vector3i) -> void: _agent_grid_pos = to_c)

func set_rig_active(active: bool) -> void:
	is_active_rig = active
	visible = active
	if camera != null:
		camera.current = active
	if active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		EventBus.cursor_cell_hovered.emit(_cursor_cell, true)

func recalibrate_gyro() -> void:
	_gyro_yaw_offset = 0.0
	_gyro_pitch_offset = 0.0
	var center_x: float = float(_grid_size.x - 1) * GameConstants.CELL_SIZE * 0.5
	var center_z: float = float(_grid_size.y - 1) * GameConstants.CELL_SIZE * 0.5
	_continuous_pointer_xz = Vector2(center_x, center_z)
	_apply_orbital_transform()
	EventBus.xai_rule_triggered.emit(0, "DECK-GYRO", "Giroscopio recalibrado y centrado en el tablero.")

func _recenter_pivot() -> void:
	var center_x: float = float(_grid_size.x - 1) * GameConstants.CELL_SIZE * 0.5
	var center_z: float = float(_grid_size.y - 1) * GameConstants.CELL_SIZE * 0.5
	camera_pivot.position = Vector3(center_x, 0.0, center_z)
	_continuous_pointer_xz = Vector2(float(_cursor_cell.x) * GameConstants.CELL_SIZE, float(_cursor_cell.y) * GameConstants.CELL_SIZE)

func _apply_orbital_transform() -> void:
	var total_yaw: float = _base_orbital_yaw + _gyro_yaw_offset
	var total_pitch: float = clampf(_base_orbital_pitch + _gyro_pitch_offset, deg_to_rad(-82.0), deg_to_rad(-22.0))
	camera_pivot.rotation = Vector3(total_pitch, total_yaw, 0.0)
	if camera != null:
		camera.position = Vector3(0.0, 0.0, _orbital_distance)
		camera.rotation = Vector3.ZERO

func _on_god_tool_changed(new_tool: GameConstants.GodTool) -> void:
	_active_tool = new_tool

func _on_world_truth_changed(truth_snapshot: Dictionary) -> void:
	var new_size: Vector2i = truth_snapshot.get("grid_size", GameConstants.DEFAULT_GRID_SIZE) as Vector2i
	if new_size != _grid_size:
		_grid_size = new_size
		_cursor_cell = Vector2i(
			clampi(_cursor_cell.x, 0, _grid_size.x - 1),
			clampi(_cursor_cell.y, 0, _grid_size.y - 1)
		)
		_recenter_pivot()
		_apply_orbital_transform()

func _process(delta: float) -> void:
	if not is_active_rig or not GameConstants.is_gameplay_active:
		return

	if _follow_agent:
		var agent_world: Vector3 = GameConstants.board_global_transform * GameConstants.grid3_to_world(_agent_grid_pos, 0.5)
		camera_pivot.global_position = camera_pivot.global_position.lerp(agent_world, clampf(delta * 5.0, 0.0, 1.0))
	else:
		var center_x: float = float(_grid_size.x - 1) * GameConstants.CELL_SIZE * 0.5
		var center_z: float = float(_grid_size.y - 1) * GameConstants.CELL_SIZE * 0.5
		camera_pivot.position = camera_pivot.position.lerp(Vector3(center_x, 0.0, center_z), clampf(delta * 4.0, 0.0, 1.0))

	if _stick_move_cooldown > 0.0:
		_stick_move_cooldown -= delta

	# Gatillo derecho R2: colocar/quitar elemento en la celda bajo el cursor
	var r2_trigger: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	if r2_trigger > 0.55 and not _r2_was_pressed:
		_r2_was_pressed = true
		EventBus.god_action_requested.emit(_cursor_cell, _active_tool)
	elif r2_trigger < 0.25:
		_r2_was_pressed = false

	# Lectura nativa del Giroscopio
	var gyro: Vector3 = Input.get_gyroscope()
	var l2_trigger: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var is_precision_pointer_mode: bool = (l2_trigger > 0.35)

	if gyro_enabled and gyro.length_squared() > 0.0001:
		if is_precision_pointer_mode:
			var max_x: float = float(_grid_size.x - 1) * GameConstants.CELL_SIZE
			var max_z: float = float(_grid_size.y - 1) * GameConstants.CELL_SIZE
			_continuous_pointer_xz.x = clampf(_continuous_pointer_xz.x - gyro.y * 8.0 * delta, 0.0, max_x)
			_continuous_pointer_xz.y = clampf(_continuous_pointer_xz.y - gyro.x * 8.0 * delta, 0.0, max_z)
			var gx: int = int(floor((_continuous_pointer_xz.x + GameConstants.CELL_SIZE * 0.5) / GameConstants.CELL_SIZE))
			var gz: int = int(floor((_continuous_pointer_xz.y + GameConstants.CELL_SIZE * 0.5) / GameConstants.CELL_SIZE))
			_set_discrete_cursor(Vector2i(gx, gz))
		else:
			_gyro_yaw_offset = clampf(_gyro_yaw_offset + gyro.y * 0.85 * delta, deg_to_rad(-28.0), deg_to_rad(28.0))
			_gyro_pitch_offset = clampf(_gyro_pitch_offset + gyro.x * 0.85 * delta, deg_to_rad(-18.0), deg_to_rad(18.0))

	# Joystick Derecho: Rotacion y Zoom manual de la camara orbital
	var rx: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > 0.18:
		_base_orbital_yaw -= rx * 1.6 * delta
	if absf(ry) > 0.18:
		_orbital_distance = clampf(_orbital_distance + ry * 7.5 * delta, 6.5, 22.0)

	# Joystick Izquierdo: Movimiento baldosa por baldosa
	var lx: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ly: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if _stick_move_cooldown <= 0.0:
		if absf(lx) > 0.55:
			_move_cursor_by(Vector2i(signi(int(round(lx))), 0))
			_stick_move_cooldown = 0.18
		elif absf(ly) > 0.55:
			_move_cursor_by(Vector2i(0, signi(int(round(ly)))))
			_stick_move_cooldown = 0.18

	_apply_orbital_transform()

func _move_cursor_by(delta_cell: Vector2i) -> void:
	var target: Vector2i = Vector2i(
		clampi(_cursor_cell.x + delta_cell.x, 0, _grid_size.x - 1),
		clampi(_cursor_cell.y + delta_cell.y, 0, _grid_size.y - 1)
	)
	_set_discrete_cursor(target)
	_continuous_pointer_xz = Vector2(float(_cursor_cell.x) * GameConstants.CELL_SIZE, float(_cursor_cell.y) * GameConstants.CELL_SIZE)

func _set_discrete_cursor(cell: Vector2i) -> void:
	var clamped: Vector2i = Vector2i(
		clampi(cell.x, 0, _grid_size.x - 1),
		clampi(cell.y, 0, _grid_size.y - 1)
	)
	if clamped != _cursor_cell:
		_cursor_cell = clamped
		EventBus.cursor_cell_hovered.emit(_cursor_cell, true)

func _cycle_tool(offset: int) -> void:
	var count: int = GameConstants.get_tool_count()
	var next_idx: int = posmod(int(_active_tool) + offset, count)
	EventBus.god_tool_changed.emit(next_idx as GameConstants.GodTool)

func _unhandled_input(event: InputEvent) -> void:
	if not is_active_rig or not GameConstants.is_gameplay_active:
		return

	# Pantalla Tactil
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed and camera != null:
			var ray_origin: Vector3 = camera.project_ray_origin(st.position)
			var ray_normal: Vector3 = camera.project_ray_normal(st.position)
			var cell: Vector2i = GameConstants.world_ray_to_grid(ray_origin, ray_normal, _grid_size)
			if cell != Vector2i(-1, -1):
				_set_discrete_cursor(cell)
				EventBus.god_action_requested.emit(cell, _active_tool)
				get_viewport().set_input_as_handled()
		return

	# Clic izquierdo de raton cuando se prueba modo Deck en PC
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and camera != null:
			var ray_origin: Vector3 = camera.project_ray_origin(mb.position)
			var ray_normal: Vector3 = camera.project_ray_normal(mb.position)
			var cell: Vector2i = GameConstants.world_ray_to_grid(ray_origin, ray_normal, _grid_size)
			if cell != Vector2i(-1, -1):
				_set_discrete_cursor(cell)
				EventBus.god_action_requested.emit(cell, _active_tool)
				get_viewport().set_input_as_handled()
		return

	# Esquema unificado de los 4 botones principales configurables (Gamepad y Teclado)
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

	# Cruceta D-Pad y botones adicionales de Gamepad
	if event is InputEventJoypadButton:
		var jb: InputEventJoypadButton = event as InputEventJoypadButton
		if not jb.pressed:
			return
		match jb.button_index:
			JOY_BUTTON_DPAD_UP:
				_move_cursor_by(Vector2i(0, -1))
			JOY_BUTTON_DPAD_DOWN:
				_move_cursor_by(Vector2i(0, 1))
			JOY_BUTTON_DPAD_LEFT:
				_move_cursor_by(Vector2i(-1, 0))
			JOY_BUTTON_DPAD_RIGHT:
				_move_cursor_by(Vector2i(1, 0))
			JOY_BUTTON_LEFT_SHOULDER:
				_cycle_tool(-1)
			JOY_BUTTON_BACK:
				recalibrate_gyro()
		get_viewport().set_input_as_handled()
		return

	# Teclado de pruebas en modo Deck (WASD mueve cursor, Enter coloca)
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		match ke.keycode:
			KEY_W:
				_move_cursor_by(Vector2i(0, -1))
			KEY_S:
				_move_cursor_by(Vector2i(0, 1))
			KEY_A:
				_move_cursor_by(Vector2i(-1, 0))
			KEY_D:
				_move_cursor_by(Vector2i(1, 0))
			KEY_ENTER, KEY_KP_ENTER:
				EventBus.god_action_requested.emit(_cursor_cell, _active_tool)
			KEY_C:
				recalibrate_gyro()
			KEY_N:
				EventBus.sim_control_requested.emit("STEP")
