class_name RigDeck_Gyro
extends Node3D
## Sistema Multi-Camara: RigDeck_Gyro (Modo 2 - Steam Deck / Gamepad / Tactil)
## Implementa camara orbital centrada en el tablero, lectura nativa de giroscopio
## (Input.get_gyroscope()) con Funcion A (Inclinacion Orbital) y Funcion B
## (Puntero Giroscopico con L2), soporte D-Pad/Sticks y pantalla tactil usando
## GameConstants.world_ray_to_grid para precision milimetrica con el tablero rotado.

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
	EventBus.xai_rule_triggered.emit(0, "DECK-GYRO", "Giroscopio de Steam Deck recalibrado y centrado en el tablero.")

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
	if not is_active_rig:
		return

	if _stick_move_cooldown > 0.0:
		_stick_move_cooldown -= delta

	# Lectura nativa del Giroscopio (Seccion 4.2)
	var gyro: Vector3 = Input.get_gyroscope()
	var l2_trigger: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var is_precision_pointer_mode: bool = (l2_trigger > 0.35)

	if gyro_enabled and gyro.length_squared() > 0.0001:
		if is_precision_pointer_mode:
			# Funcion B: Puntero Giroscopico de Precision sobre el plano local del tablero al mantener L2
			var max_x: float = float(_grid_size.x - 1) * GameConstants.CELL_SIZE
			var max_z: float = float(_grid_size.y - 1) * GameConstants.CELL_SIZE
			_continuous_pointer_xz.x = clampf(_continuous_pointer_xz.x - gyro.y * 8.0 * delta, 0.0, max_x)
			_continuous_pointer_xz.y = clampf(_continuous_pointer_xz.y - gyro.x * 8.0 * delta, 0.0, max_z)
			var gx: int = int(floor((_continuous_pointer_xz.x + GameConstants.CELL_SIZE * 0.5) / GameConstants.CELL_SIZE))
			var gz: int = int(floor((_continuous_pointer_xz.y + GameConstants.CELL_SIZE * 0.5) / GameConstants.CELL_SIZE))
			_set_discrete_cursor(Vector2i(gx, gz))
		else:
			# Funcion A: Inclinacion Orbital de Maqueta con paralaje natural
			_gyro_yaw_offset = clampf(_gyro_yaw_offset + gyro.y * 0.85 * delta, deg_to_rad(-28.0), deg_to_rad(28.0))
			_gyro_pitch_offset = clampf(_gyro_pitch_offset + gyro.x * 0.85 * delta, deg_to_rad(-18.0), deg_to_rad(18.0))

	# Joystick Derecho: Rotacion y Zoom manual de la camara orbital
	var rx: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > 0.18:
		_base_orbital_yaw -= rx * 1.6 * delta
	if absf(ry) > 0.18:
		_orbital_distance = clampf(_orbital_distance + ry * 7.5 * delta, 6.5, 22.0)

	# Joystick Izquierdo: Movimiento baldosa por baldosa con cooldown
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
	var count: int = 5
	var next_idx: int = posmod(int(_active_tool) + offset, count)
	EventBus.god_tool_changed.emit(next_idx as GameConstants.GodTool)

func _unhandled_input(event: InputEvent) -> void:
	if not is_active_rig:
		return

	# Pantalla Tactil (InputEventScreenTouch - Seccion 4.2 + Transformacion Local Seccion 2.2.3)
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

	# Soporte clic izquierdo de raton cuando se prueba el modo Steam Deck en PC
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

	# Botones de Gamepad (Steam Deck)
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
			JOY_BUTTON_A:
				EventBus.god_action_requested.emit(_cursor_cell, _active_tool)
			JOY_BUTTON_LEFT_SHOULDER:
				_cycle_tool(-1)
			JOY_BUTTON_RIGHT_SHOULDER:
				_cycle_tool(1)
			JOY_BUTTON_Y:
				EventBus.sim_control_requested.emit("TOGGLE_PAUSE")
			JOY_BUTTON_X:
				EventBus.sim_control_requested.emit("STEP")
			JOY_BUTTON_BACK, JOY_BUTTON_RIGHT_STICK:
				recalibrate_gyro()
		get_viewport().set_input_as_handled()
		return

	# Teclas equivalentes para probar el modo Steam Deck desde teclado PC (WASD mueve cursor, Flechas giran el tablero)
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
			KEY_Q:
				_cycle_tool(-1)
			KEY_E:
				_cycle_tool(1)
			KEY_C:
				recalibrate_gyro()
			KEY_SPACE:
				EventBus.sim_control_requested.emit("TOGGLE_PAUSE")
			KEY_N:
				EventBus.sim_control_requested.emit("STEP")
