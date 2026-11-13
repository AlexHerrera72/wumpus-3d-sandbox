class_name RigVR_Quest
extends XROrigin3D
## Sistema Multi-Camara: RigVR_Quest (Modo 3 - Realidad Virtual OpenXR Meta Quest)
## Configura XROrigin3D a escala maqueta frente al tablero, XRController3D derecho
## con rayo laser 3D (ImmediateMesh) que intersecta el plano local del tablero
## rotado mediante GameConstants.world_ray_to_grid, y XRController3D izquierdo
## con acoplamiento para el panel de auditoria XAI de muneca.

const VRWristPanelScript = preload("res://ui_xai/VR_WristPanel3D.gd")

var xr_camera: XRCamera3D
var right_controller: XRController3D
var left_controller: XRController3D
var wrist_panel: Node3D

var is_active_rig: bool = false
var _grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var _active_tool: GameConstants.GodTool = GameConstants.GodTool.TOGGLE_PIT
var _hovered_cell: Vector2i = Vector2i.ZERO
var _is_hover_valid: bool = false

var _laser_mesh_inst: MeshInstance3D
var _laser_immediate: ImmediateMesh
var _laser_mat: StandardMaterial3D

func _ready() -> void:
	world_scale = 1.0
	_build_xr_nodes()
	_position_in_front_of_tabletop()

	EventBus.god_tool_changed.connect(_on_god_tool_changed)
	EventBus.world_truth_changed.connect(_on_world_truth_changed)

func _build_xr_nodes() -> void:
	xr_camera = XRCamera3D.new()
	xr_camera.name = "XRCamera3D"
	xr_camera.position = Vector3(0.0, 1.65, 0.0)
	add_child(xr_camera)

	# Controlador Derecho: Laser de seleccion Modo Dios
	right_controller = XRController3D.new()
	right_controller.name = "RightHandController"
	right_controller.tracker = &"right_hand"
	right_controller.pose = &"aim"
	right_controller.button_pressed.connect(_on_right_controller_button_pressed)
	add_child(right_controller)

	_laser_immediate = ImmediateMesh.new()
	_laser_mesh_inst = MeshInstance3D.new()
	_laser_mesh_inst.name = "LaserBeam3D"
	_laser_mesh_inst.mesh = _laser_immediate
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.albedo_color = Color(0.20, 0.95, 1.0)
	_laser_mesh_inst.material_override = _laser_mat
	right_controller.add_child(_laser_mesh_inst)

	# Controlador Izquierdo: Panel de muneca VR_WristPanel3D
	left_controller = XRController3D.new()
	left_controller.name = "LeftHandController"
	left_controller.tracker = &"left_hand"
	left_controller.pose = &"grip"
	left_controller.button_pressed.connect(_on_left_controller_button_pressed)
	add_child(left_controller)

	wrist_panel = VRWristPanelScript.new()
	wrist_panel.name = "VR_WristPanel3D"
	left_controller.add_child(wrist_panel)

func _position_in_front_of_tabletop() -> void:
	var center_x: float = float(_grid_size.x - 1) * GameConstants.CELL_SIZE * 0.5
	var max_z: float = float(_grid_size.y - 1) * GameConstants.CELL_SIZE
	position = Vector3(center_x, 3.2, max_z + 5.5)

func set_rig_active(active: bool) -> void:
	is_active_rig = active
	visible = active
	current = active
	if xr_camera != null:
		xr_camera.current = active

func _on_god_tool_changed(new_tool: GameConstants.GodTool) -> void:
	_active_tool = new_tool

func _on_world_truth_changed(truth_snapshot: Dictionary) -> void:
	var new_size: Vector2i = truth_snapshot.get("grid_size", GameConstants.DEFAULT_GRID_SIZE) as Vector2i
	if new_size != _grid_size:
		_grid_size = new_size
		_position_in_front_of_tabletop()

func _process(_delta: float) -> void:
	if not is_active_rig or right_controller == null:
		return

	var origin: Vector3 = right_controller.global_position
	var forward_dir: Vector3 = -right_controller.global_transform.basis.z.normalized()

	# Interseccion en el espacio local del tablero giratorio (Seccion 2.2.3)
	var cell: Vector2i = GameConstants.world_ray_to_grid(origin, forward_dir, _grid_size)
	var valid: bool = (cell != Vector2i(-1, -1))

	var local_end: Vector3 = Vector3(0.0, 0.0, -12.0)
	if valid:
		var cell_board_local: Vector3 = GameConstants.grid_to_world(cell, 0.05)
		var cell_world: Vector3 = GameConstants.board_global_transform * cell_board_local
		local_end = right_controller.to_local(cell_world)

	if cell != _hovered_cell or valid != _is_hover_valid:
		_hovered_cell = cell
		_is_hover_valid = valid
		EventBus.cursor_cell_hovered.emit(_hovered_cell, _is_hover_valid)

	_draw_laser_line(local_end)

func _draw_laser_line(local_end: Vector3) -> void:
	if _laser_immediate == null:
		return
	_laser_immediate.clear_surfaces()
	_laser_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	_laser_immediate.surface_add_vertex(Vector3.ZERO)
	_laser_immediate.surface_add_vertex(local_end)
	_laser_immediate.surface_end()

func _on_right_controller_button_pressed(button_name: String) -> void:
	if not is_active_rig:
		return
	if button_name == "trigger_click":
		if _is_hover_valid:
			EventBus.god_action_requested.emit(_hovered_cell, _active_tool)
	elif button_name == "ax_button":
		var next_idx: int = posmod(int(_active_tool) + 1, 5)
		EventBus.god_tool_changed.emit(next_idx as GameConstants.GodTool)

func _on_left_controller_button_pressed(button_name: String) -> void:
	if not is_active_rig:
		return
	if button_name == "by_button":
		EventBus.sim_control_requested.emit("TOGGLE_PAUSE")
	elif button_name == "trigger_click":
		EventBus.sim_control_requested.emit("STEP")
