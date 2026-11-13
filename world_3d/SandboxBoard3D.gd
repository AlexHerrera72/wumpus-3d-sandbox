class_name SandboxBoard3D
extends Node3D
## Entorno Visual 3D: SandboxBoard3D
## Construye y mantiene la matriz 3D de baldosas Tile3D, el indicador Cursor3D,
## el visualizador de rutas A* y el Agente Explorador unificados bajo el pivote
## giratorio central BoardTurntable3D. Soporta rotacion suave y por pasos de 90 deg
## con las flechas del teclado (acciones configurables) y actualiza en tiempo real
## GameConstants.board_global_transform para mantener raycasting milimetrico.

const TURNTABLE_YAW_SPEED_RAD: float = deg_to_rad(90.0)
const TURNTABLE_TILT_SPEED_RAD: float = deg_to_rad(45.0)
const MAX_TILT_RAD: float = deg_to_rad(25.0)
const SMOOTH_LERP_SPEED: float = 10.0

var grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var tiles: Dictionary = {} # Vector2i -> Tile3D

var _board_turntable: Node3D
var _board_content_origin: Node3D
var _tiles_container: Node3D
var _cursor_3d: MeshInstance3D
var _cursor_mat: StandardMaterial3D
var _table_pedestal: MeshInstance3D
var _path_visualizer: PathVisualizer3D
var _agent_visual: AgentVisual3D

var _target_yaw: float = 0.0
var _current_yaw: float = 0.0
var _target_tilt: float = 0.0
var _current_tilt: float = 0.0

func _ready() -> void:
	# Pivote central del tablero (BoardTurntable3D) situado en el centro geometrico
	_board_turntable = Node3D.new()
	_board_turntable.name = "BoardTurntable3D"
	add_child(_board_turntable)

	# Contenedor interno desplazado por -Centro para que todas las celdas conserven
	# su coordenada local exacta (x * CELL_SIZE, 0, y * CELL_SIZE)
	_board_content_origin = Node3D.new()
	_board_content_origin.name = "BoardContentOrigin3D"
	_board_turntable.add_child(_board_content_origin)

	_tiles_container = Node3D.new()
	_tiles_container.name = "TilesContainer"
	_board_content_origin.add_child(_tiles_container)

	_build_table_pedestal()
	_build_cursor_3d()

	_path_visualizer = PathVisualizer3D.new()
	_path_visualizer.name = "PathVisualizer3D"
	_board_content_origin.add_child(_path_visualizer)

	_agent_visual = AgentVisual3D.new()
	_agent_visual.name = "AgentVisual3D"
	_board_content_origin.add_child(_agent_visual)

	_rebuild_tile_grid(GameConstants.DEFAULT_GRID_SIZE)
	_sync_board_global_transform()

	EventBus.world_truth_changed.connect(_on_world_truth_changed)
	EventBus.epistemic_state_updated.connect(_on_epistemic_state_updated)
	EventBus.cursor_cell_hovered.connect(_on_cursor_cell_hovered)
	EventBus.board_rotation_reset_requested.connect(reset_board_rotation)

func _process(delta: float) -> void:
	_process_turntable_rotation_input(delta)
	_current_yaw = lerp_angle(_current_yaw, _target_yaw, clampf(delta * SMOOTH_LERP_SPEED, 0.0, 1.0))
	_current_tilt = lerpf(_current_tilt, _target_tilt, clampf(delta * SMOOTH_LERP_SPEED, 0.0, 1.0))

	if _board_turntable != null:
		_board_turntable.rotation = Vector3(_current_tilt, _current_yaw, 0.0)

	_sync_board_global_transform()

func _process_turntable_rotation_input(delta: float) -> void:
	# Evitar que Shift + Flecha rote de forma continua si ya hizo el snap de 90 grados
	if Input.is_key_pressed(KEY_SHIFT):
		return

	if Input.is_action_pressed("board_rotate_left"):
		_target_yaw -= TURNTABLE_YAW_SPEED_RAD * delta
	if Input.is_action_pressed("board_rotate_right"):
		_target_yaw += TURNTABLE_YAW_SPEED_RAD * delta
	if Input.is_action_pressed("board_tilt_up"):
		_target_tilt = clampf(_target_tilt + TURNTABLE_TILT_SPEED_RAD * delta, 0.0, MAX_TILT_RAD)
	if Input.is_action_pressed("board_tilt_down"):
		_target_tilt = clampf(_target_tilt - TURNTABLE_TILT_SPEED_RAD * delta, 0.0, MAX_TILT_RAD)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("board_reset_rotation", false, true):
		reset_board_rotation()
		get_viewport().set_input_as_handled()
		return

	# Snap exacto de 90 grados al pulsar Shift + Giro Izquierda/Derecha (Seccion 2.2.2)
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and not ke.echo and ke.shift_pressed:
			if ke.keycode == PlatformManager.get_action_keycode("board_rotate_left"):
				snap_rotate_90_degrees(-1)
				get_viewport().set_input_as_handled()
			elif ke.keycode == PlatformManager.get_action_keycode("board_rotate_right"):
				snap_rotate_90_degrees(1)
				get_viewport().set_input_as_handled()

func snap_rotate_90_degrees(direction_sign: int) -> void:
	var step_rad: float = PI * 0.5
	var snapped_base: float = roundf(_target_yaw / step_rad) * step_rad
	_target_yaw = snapped_base + float(direction_sign) * step_rad

func reset_board_rotation() -> void:
	_target_yaw = 0.0
	_target_tilt = 0.0

func _sync_board_global_transform() -> void:
	if _board_content_origin != null and _board_content_origin.is_inside_tree():
		GameConstants.board_global_transform = _board_content_origin.global_transform

func _update_turntable_pivot_and_pedestal() -> void:
	var center_x: float = float(grid_size.x - 1) * GameConstants.CELL_SIZE * 0.5
	var center_z: float = float(grid_size.y - 1) * GameConstants.CELL_SIZE * 0.5
	var geometric_center: Vector3 = Vector3(center_x, 0.0, center_z)

	if _board_turntable != null:
		_board_turntable.position = geometric_center
	if _board_content_origin != null:
		_board_content_origin.position = -geometric_center

	if _table_pedestal != null:
		var width_world: float = float(grid_size.x) * GameConstants.CELL_SIZE + 1.2
		var depth_world: float = float(grid_size.y) * GameConstants.CELL_SIZE + 1.2
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(width_world, 0.35, depth_world)
		_table_pedestal.mesh = box
		_table_pedestal.position = Vector3(center_x, -0.38, center_z)

func _build_table_pedestal() -> void:
	_table_pedestal = MeshInstance3D.new()
	_table_pedestal.name = "TabletopPedestal"
	var pedestal_mat: StandardMaterial3D = StandardMaterial3D.new()
	pedestal_mat.albedo_color = Color(0.11, 0.12, 0.15)
	pedestal_mat.roughness = 0.85
	_table_pedestal.material_override = pedestal_mat
	_board_content_origin.add_child(_table_pedestal)

func _build_cursor_3d() -> void:
	_cursor_3d = MeshInstance3D.new()
	_cursor_3d.name = "Cursor3D"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.78
	torus.outer_radius = 0.90
	_cursor_3d.mesh = torus

	_cursor_mat = StandardMaterial3D.new()
	_cursor_mat.albedo_color = Color(0.25, 0.95, 1.0)
	_cursor_mat.emission_enabled = true
	_cursor_mat.emission = Color(0.20, 0.85, 1.0)
	_cursor_mat.emission_energy_multiplier = 1.2
	_cursor_3d.material_override = _cursor_mat
	_cursor_3d.position = Vector3(0.0, 0.08, 0.0)
	_board_content_origin.add_child(_cursor_3d)

func _rebuild_tile_grid(new_size: Vector2i) -> void:
	grid_size = new_size
	for child: Node in _tiles_container.get_children():
		child.queue_free()
	tiles.clear()

	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var coords: Vector2i = Vector2i(x, y)
			var tile: Tile3D = Tile3D.new()
			tile.name = "Tile_%d_%d" % [x, y]
			_tiles_container.add_child(tile)
			tile.setup_tile(coords)
			tiles[coords] = tile

	_update_turntable_pivot_and_pedestal()
	_sync_board_global_transform()

func _on_world_truth_changed(truth_snapshot: Dictionary) -> void:
	var snap_size: Vector2i = truth_snapshot.get("grid_size", GameConstants.DEFAULT_GRID_SIZE) as Vector2i
	if snap_size != grid_size or tiles.is_empty():
		_rebuild_tile_grid(snap_size)

	var pits_arr: Array = truth_snapshot.get("pits", [])
	var walls_arr: Array = truth_snapshot.get("walls", [])
	var breeze_arr: Array = truth_snapshot.get("breeze_cells", [])
	var stench_arr: Array = truth_snapshot.get("stench_cells", [])
	var wumpus_pos: Vector2i = truth_snapshot.get("wumpus_pos", Vector2i(-1, -1)) as Vector2i
	var wumpus_alive: bool = bool(truth_snapshot.get("wumpus_alive", true))
	var gold_pos: Vector2i = truth_snapshot.get("gold_pos", Vector2i(-1, -1)) as Vector2i
	var gold_collected: bool = bool(truth_snapshot.get("gold_collected", false))

	for coords: Vector2i in tiles.keys():
		var tile: Tile3D = tiles[coords] as Tile3D
		var has_pit: bool = pits_arr.has(coords)
		var has_wall: bool = walls_arr.has(coords)
		var has_wumpus_here: bool = (wumpus_pos == coords)
		var has_gold_here: bool = (not gold_collected) and (gold_pos == coords)
		var has_breeze: bool = breeze_arr.has(coords)
		var has_stench: bool = stench_arr.has(coords)

		tile.update_truth_props(
			has_pit,
			has_wumpus_here,
			wumpus_alive,
			has_wall,
			has_gold_here,
			has_breeze,
			has_stench
		)

func _on_epistemic_state_updated(visual_states: Dictionary, _current_path: Array[Vector2i]) -> void:
	for coords: Vector2i in visual_states.keys():
		if tiles.has(coords):
			var tile: Tile3D = tiles[coords] as Tile3D
			var v_state: GameConstants.CellVisualState = visual_states[coords] as GameConstants.CellVisualState
			tile.set_visual_belief_state(v_state)

func _on_cursor_cell_hovered(cell: Vector2i, is_valid: bool) -> void:
	if _cursor_3d == null:
		return
	if not is_valid or cell.x < 0 or cell.x >= grid_size.x or cell.y < 0 or cell.y >= grid_size.y:
		_cursor_3d.visible = false
		return

	_cursor_3d.visible = true
	_cursor_3d.position = GameConstants.grid_to_world(cell, 0.08)
	if cell == Vector2i.ZERO:
		_cursor_mat.albedo_color = Color(1.0, 0.45, 0.25)
		_cursor_mat.emission = Color(0.95, 0.35, 0.15)
	else:
		_cursor_mat.albedo_color = Color(0.25, 0.95, 1.0)
		_cursor_mat.emission = Color(0.20, 0.85, 1.0)
