class_name RigPC_FreeCam
extends Node3D
## Sistema Multi-Camara: RigPC_FreeCam (Modo 1 - Escritorio PC)
## Implementa vuelo libre 3D con Click Derecho + WASD/QE/Shift y proyeccion
## matematica en el espacio local del tablero (GameConstants.world_ray_to_grid)
## para que el selector de baldosas funcione con exactitud incluso con el tablero rotado.

const BASE_FLY_SPEED: float = 8.5
const FAST_SPEED_MULTIPLIER: float = 2.0
const MOUSE_SENSITIVITY: float = 0.0028
const MAX_PITCH_RAD: float = deg_to_rad(85.0)

var camera: Camera3D
var is_active_rig: bool = false
var is_flying: bool = false

var _yaw: float = -0.55
var _pitch: float = -0.68
var _grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var _active_tool: GameConstants.GodTool = GameConstants.GodTool.TOGGLE_PIT
var _hovered_cell: Vector2i = Vector2i.ZERO
var _is_hover_valid: bool = false

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "PCFreeCamera3D"
	camera.fov = 60.0
	add_child(camera)

	_reset_camera_pose()

	EventBus.god_tool_changed.connect(_on_god_tool_changed)
	EventBus.world_truth_changed.connect(_on_world_truth_changed)

func set_rig_active(active: bool) -> void:
	is_active_rig = active
	visible = active
	if camera != null:
		camera.current = active
	if not active and is_flying:
		is_flying = false
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

func _process(delta: float) -> void:
	if not is_active_rig or camera == null:
		return

	if is_flying:
		_process_free_flight(delta)
	else:
		_update_board_raycast()

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
		global_position.y = clampf(global_position.y, 1.2, 28.0)

func _update_board_raycast() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var mouse_pos: Vector2 = viewport.get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = camera.project_ray_normal(mouse_pos)

	# Transformacion al espacio local del tablero giratorio (Seccion 2.2.3)
	var cell: Vector2i = GameConstants.world_ray_to_grid(ray_origin, ray_normal, _grid_size)
	var valid: bool = (cell != Vector2i(-1, -1))

	if cell != _hovered_cell or valid != _is_hover_valid:
		_hovered_cell = cell
		_is_hover_valid = valid
		EventBus.cursor_cell_hovered.emit(_hovered_cell, _is_hover_valid)

func _unhandled_input(event: InputEvent) -> void:
	if not is_active_rig:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				is_flying = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				is_flying = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not is_flying:
			_update_board_raycast()
			if _is_hover_valid:
				EventBus.god_action_requested.emit(_hovered_cell, _active_tool)
				get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and is_flying:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_yaw -= mm.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - mm.relative.y * MOUSE_SENSITIVITY, -MAX_PITCH_RAD, MAX_PITCH_RAD)
		_apply_rotation()
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
				EventBus.god_tool_changed.emit(GameConstants.GodTool.CLEAR_CELL)
			KEY_SPACE:
				if not is_flying:
					EventBus.sim_control_requested.emit("TOGGLE_PAUSE")
					get_viewport().set_input_as_handled()
			KEY_N:
				if not is_flying:
					EventBus.sim_control_requested.emit("STEP")
					get_viewport().set_input_as_handled()
			KEY_R:
				if not is_flying:
					EventBus.sim_control_requested.emit("RESET")
					get_viewport().set_input_as_handled()
