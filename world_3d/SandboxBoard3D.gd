class_name SandboxBoard3D
extends Node3D
## Entorno Visual 3D: SandboxBoard3D
## Gestiona hasta 5 pisos de mazmorra dentro del pivote central BoardTurntable3D.
## El piso seleccionado se centra suavemente en Y=0 a escala 1.0 e iluminado,
## mientras los pisos superiores e inferiores se desplazan arriba/abajo, se alejan
## y se oscurecen proporcionalmente a su distancia.

const TURNTABLE_YAW_SPEED_RAD: float = deg_to_rad(90.0)
const TURNTABLE_TILT_SPEED_RAD: float = deg_to_rad(45.0)
const MAX_TILT_RAD: float = deg_to_rad(25.0)
const SMOOTH_LERP_SPEED: float = 10.0

const FLOOR_SWITCH_ANIM_DUR: float = 0.46
const INACTIVE_FLOOR_Z_STEP: float = -2.0

var grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var floor_count: int = 1
var active_view_floor: int = 0

var tiles: Dictionary = {} # Vector3i -> Tile3D

var _board_turntable: Node3D
var _floor_pivots: Array[Node3D] = []
var _floor_contents: Array[Node3D] = []
var _tiles_containers: Array[Node3D] = []
var _pedestals: Array[MeshInstance3D] = []
var _pedestal_mats: Array[StandardMaterial3D] = []
var _path_visualizers: Array[PathVisualizer3D] = []

var _cursor_3d: MeshInstance3D
var _cursor_mat: StandardMaterial3D
var _agent_visual: AgentVisual3D
var _agent_current_floor: int = 0

var _floor_anim_tween: Tween
var _target_yaw: float = 0.0
var _current_yaw: float = 0.0
var _target_tilt: float = 0.0
var _current_tilt: float = 0.0

func _ready() -> void:
	_board_turntable = Node3D.new()
	_board_turntable.name = "BoardTurntable3D"
	add_child(_board_turntable)

	_build_floor_layers()
	_build_cursor_3d()

	_agent_visual = AgentVisual3D.new()
	_agent_visual.name = "AgentVisual3D"
	_floor_contents[0].add_child(_agent_visual)

	_rebuild_tile_grids(GameConstants.DEFAULT_GRID_SIZE, 1)
	_apply_floor_focus_visuals(true)
	_sync_board_global_transform()

	EventBus.world_truth_changed.connect(_on_world_truth_changed)
	EventBus.epistemic_multifloor_updated.connect(_on_epistemic_multifloor_updated)
	EventBus.cursor_cell_hovered.connect(_on_cursor_cell_hovered)
	EventBus.board_rotation_reset_requested.connect(reset_board_rotation)
	EventBus.active_floor_changed.connect(_on_active_floor_changed)
	EventBus.agent_transform_3d_updated.connect(_on_agent_transform_3d_updated)
	EventBus.agent_teleported.connect(_on_agent_teleported)

func _build_floor_layers() -> void:
	for fl: int in range(GameConstants.MAX_FLOORS):
		var pivot: Node3D = Node3D.new()
		pivot.name = "FloorPivot_%d" % [fl]
		_board_turntable.add_child(pivot)
		_floor_pivots.append(pivot)

		var content: Node3D = Node3D.new()
		content.name = "FloorContentOrigin_%d" % [fl]
		pivot.add_child(content)
		_floor_contents.append(content)

		var t_cont: Node3D = Node3D.new()
		t_cont.name = "TilesContainer_%d" % [fl]
		content.add_child(t_cont)
		_tiles_containers.append(t_cont)

		var ped: MeshInstance3D = MeshInstance3D.new()
		ped.name = "TabletopPedestal_%d" % [fl]
		var ped_mat: StandardMaterial3D = StandardMaterial3D.new()
		ped_mat.albedo_color = Color(0.11, 0.12, 0.15)
		ped_mat.roughness = 0.85
		ped.material_override = ped_mat
		content.add_child(ped)
		_pedestals.append(ped)
		_pedestal_mats.append(ped_mat)

		var pv: PathVisualizer3D = PathVisualizer3D.new()
		pv.name = "PathVisualizer3D_%d" % [fl]
		pv.assigned_floor = fl
		content.add_child(pv)
		_path_visualizers.append(pv)

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
	_floor_contents[0].add_child(_cursor_3d)

func _process(delta: float) -> void:
	if GameConstants.is_gameplay_active:
		_process_turntable_rotation_input(delta)
	else:
		_target_yaw += deg_to_rad(8.0) * delta

	_current_yaw = lerp_angle(_current_yaw, _target_yaw, clampf(delta * SMOOTH_LERP_SPEED, 0.0, 1.0))
	_current_tilt = lerpf(_current_tilt, _target_tilt, clampf(delta * SMOOTH_LERP_SPEED, 0.0, 1.0))

	if _board_turntable != null:
		_board_turntable.rotation = Vector3(_current_tilt, _current_yaw, 0.0)

	_sync_board_global_transform()

func _process_turntable_rotation_input(delta: float) -> void:
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
	if not GameConstants.is_gameplay_active:
		return

	if event.is_action_pressed("board_reset_rotation", false, true):
		reset_board_rotation()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("floor_up", false, true):
		if floor_count >= 2:
			EventBus.active_floor_step_requested.emit(1)
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("floor_down", false, true):
		if floor_count >= 2:
			EventBus.active_floor_step_requested.emit(-1)
			get_viewport().set_input_as_handled()
		return

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
	if active_view_floor >= 0 and active_view_floor < _floor_contents.size():
		var active_content: Node3D = _floor_contents[active_view_floor]
		if active_content != null and active_content.is_inside_tree():
			GameConstants.board_global_transform = active_content.global_transform

func _update_turntable_pivots_and_pedestals() -> void:
	var center_x: float = float(grid_size.x - 1) * GameConstants.CELL_SIZE * 0.5
	var center_z: float = float(grid_size.y - 1) * GameConstants.CELL_SIZE * 0.5
	var geometric_center: Vector3 = Vector3(center_x, 0.0, center_z)

	if _board_turntable != null:
		_board_turntable.position = geometric_center

	var width_world: float = float(grid_size.x) * GameConstants.CELL_SIZE + 1.2
	var depth_world: float = float(grid_size.y) * GameConstants.CELL_SIZE + 1.2

	for fl: int in range(GameConstants.MAX_FLOORS):
		_floor_contents[fl].position = -geometric_center
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(width_world, 0.35, depth_world)
		_pedestals[fl].mesh = box
		_pedestals[fl].position = Vector3(center_x, -0.38, center_z)

func _rebuild_tile_grids(new_size: Vector2i, new_floor_count: int) -> void:
	grid_size = new_size
	floor_count = clampi(new_floor_count, 1, GameConstants.MAX_FLOORS)

	for fl: int in range(GameConstants.MAX_FLOORS):
		for child: Node in _tiles_containers[fl].get_children():
			child.queue_free()
	tiles.clear()

	for fl: int in range(floor_count):
		_floor_pivots[fl].visible = true
		for y: int in range(grid_size.y):
			for x: int in range(grid_size.x):
				var coords: Vector3i = Vector3i(x, y, fl)
				var tile: Tile3D = Tile3D.new()
				tile.name = "Tile_%d_%d_F%d" % [x, y, fl]
				_tiles_containers[fl].add_child(tile)
				tile.setup_tile(coords)
				tiles[coords] = tile

	for fl: int in range(floor_count, GameConstants.MAX_FLOORS):
		_floor_pivots[fl].visible = false

	_update_turntable_pivots_and_pedestals()
	_apply_floor_focus_visuals(true)
	_sync_board_global_transform()

func _on_active_floor_changed(new_active_floor: int, new_floor_count: int) -> void:
	active_view_floor = clampi(new_active_floor, 0, clampi(new_floor_count, 1, GameConstants.MAX_FLOORS) - 1)
	if new_floor_count != floor_count:
		_rebuild_tile_grids(grid_size, new_floor_count)
	else:
		_apply_floor_focus_visuals(false)

func _apply_floor_focus_visuals(instant: bool) -> void:
	if _cursor_3d != null and active_view_floor < _floor_contents.size():
		if _cursor_3d.get_parent() != _floor_contents[active_view_floor]:
			_cursor_3d.reparent(_floor_contents[active_view_floor], false)

	if _floor_anim_tween != null and _floor_anim_tween.is_valid():
		_floor_anim_tween.kill()

	if not instant:
		_floor_anim_tween = create_tween()
		_floor_anim_tween.set_parallel(true)

	for fl: int in range(floor_count):
		var pivot: Node3D = _floor_pivots[fl]
		var diff: int = fl - active_view_floor
		var dist: int = absi(diff)
		var is_selected: bool = (diff == 0)

		var target_pos: Vector3 = Vector3.ZERO
		var target_scale: Vector3 = Vector3.ONE
		var vis_mode: String = "ACTIVE"

		if diff > 0:
			# Piso SUPERIOR: mas alto y alejado hacia atras + cristal transparente para no tapar el piso de abajo!
			vis_mode = "ABOVE"
			var y_up: float = float(dist) * 11.2
			var z_back: float = float(dist) * -3.6
			var sc_up: float = clampf(0.72 - float(dist - 1) * 0.10, 0.42, 0.72)
			target_pos = Vector3(0.0, y_up, z_back)
			target_scale = Vector3(sc_up, sc_up, sc_up)
		elif diff < 0:
			# Piso INFERIOR: debajo, alejado y semitransparente oscuro
			vis_mode = "BELOW"
			var y_down: float = float(diff) * 8.2
			var z_back_d: float = float(dist) * -2.2
			var sc_dn: float = clampf(0.76 - float(dist - 1) * 0.10, 0.44, 0.76)
			target_pos = Vector3(0.0, y_down, z_back_d)
			target_scale = Vector3(sc_dn, sc_dn, sc_dn)

		if instant:
			pivot.position = target_pos
			pivot.scale = target_scale
		else:
			_floor_anim_tween.tween_property(pivot, "position", target_pos, FLOOR_SWITCH_ANIM_DUR).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_floor_anim_tween.tween_property(pivot, "scale", target_scale, FLOOR_SWITCH_ANIM_DUR).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

		if vis_mode == "ACTIVE":
			_pedestal_mats[fl].transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			_pedestal_mats[fl].albedo_color = Color(0.11, 0.12, 0.15, 1.0)
		elif vis_mode == "ABOVE":
			_pedestal_mats[fl].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_pedestal_mats[fl].albedo_color = Color(0.10, 0.12, 0.16, 0.08)
		else:
			_pedestal_mats[fl].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_pedestal_mats[fl].albedo_color = Color(0.05, 0.06, 0.08, 0.32)

		_path_visualizers[fl].set_dimmed(not is_selected)
		_path_visualizers[fl].visible = (vis_mode != "ABOVE")
		for coords: Vector3i in tiles.keys():
			if coords.z == fl:
				var tile: Tile3D = tiles[coords] as Tile3D
				tile.set_floor_visibility_mode(vis_mode)

func _reparent_agent_to_floor(target_floor: int) -> void:
	var fl: int = clampi(target_floor, 0, _floor_contents.size() - 1)
	if _agent_visual != null and _agent_visual.get_parent() != _floor_contents[fl]:
		_agent_visual.reparent(_floor_contents[fl], false)
	_agent_current_floor = fl

func _on_agent_transform_3d_updated(grid_pos: Vector3i, _facing_dir: Vector2i, _is_moving: bool) -> void:
	if grid_pos.z != _agent_current_floor:
		_reparent_agent_to_floor(grid_pos.z)

func _on_agent_teleported(_from_cell: Vector3i, to_cell: Vector3i) -> void:
	var speed_mult: float = clampf(GameConstants.current_speed_multiplier, 0.25, 4.0)
	var mid_delay: float = 0.34 / speed_mult
	var rep_tween: Tween = create_tween()
	rep_tween.tween_interval(mid_delay)
	rep_tween.tween_callback(func() -> void: _reparent_agent_to_floor(to_cell.z))

func _on_world_truth_changed(truth_snapshot: Dictionary) -> void:
	var snap_size: Vector2i = truth_snapshot.get("grid_size", GameConstants.DEFAULT_GRID_SIZE) as Vector2i
	var snap_floors: int = int(truth_snapshot.get("floor_count", 1))
	if snap_size != grid_size or snap_floors != floor_count or tiles.is_empty():
		_rebuild_tile_grids(snap_size, snap_floors)

	var pits_arr: Array = truth_snapshot.get("pits", [])
	var walls_arr: Array = truth_snapshot.get("walls", [])
	var wumpuses_dict: Dictionary = truth_snapshot.get("wumpuses", {})
	var arrows_arr: Array = truth_snapshot.get("arrows", [])
	var portal_colors: Dictionary = truth_snapshot.get("portal_colors", {})
	var stairs_up_dict: Dictionary = truth_snapshot.get("stairs_up", {})
	var stairs_down_dict: Dictionary = truth_snapshot.get("stairs_down", {})
	var stairs_pending_dict: Dictionary = truth_snapshot.get("stairs_pending", {})
	var breeze_arr: Array = truth_snapshot.get("breeze_cells", [])
	var stench_arr: Array = truth_snapshot.get("stench_cells", [])
	var gold_pos: Vector3i = truth_snapshot.get("gold_pos", Vector3i(-1, -1, -1)) as Vector3i
	var gold_collected: bool = bool(truth_snapshot.get("gold_collected", false))

	for coords: Vector3i in tiles.keys():
		var tile: Tile3D = tiles[coords] as Tile3D
		var has_pit: bool = pits_arr.has(coords)
		var has_wall: bool = walls_arr.has(coords)
		var has_wumpus_here: bool = wumpuses_dict.has(coords)
		var wumpus_alive: bool = bool(wumpuses_dict.get(coords, false))
		var has_gold_here: bool = (not gold_collected) and (gold_pos == coords) and (gold_pos.x >= 0)
		var p_color: String = String(portal_colors.get(coords, ""))
		var has_st_up: bool = bool(stairs_up_dict.get(coords, false))
		var has_st_down: bool = bool(stairs_down_dict.get(coords, false))
		var has_st_pending: bool = bool(stairs_pending_dict.get(coords, false))
		var has_arrow_here: bool = arrows_arr.has(coords)
		var has_breeze: bool = breeze_arr.has(coords)
		var has_stench: bool = stench_arr.has(coords)

		tile.update_truth_props(
			has_pit,
			has_wumpus_here,
			wumpus_alive,
			has_wall,
			has_gold_here,
			p_color,
			has_st_up,
			has_st_down,
			has_st_pending,
			has_arrow_here,
			has_breeze,
			has_stench
		)

func _on_epistemic_multifloor_updated(visual_states_3d: Dictionary, _current_path_3d: Array[Vector3i]) -> void:
	for coords: Vector3i in visual_states_3d.keys():
		if tiles.has(coords):
			var tile: Tile3D = tiles[coords] as Tile3D
			var v_state: GameConstants.CellVisualState = visual_states_3d[coords] as GameConstants.CellVisualState
			tile.set_visual_belief_state(v_state)

func _on_cursor_cell_hovered(cell: Vector2i, is_valid: bool) -> void:
	if _cursor_3d == null:
		return
	if not GameConstants.is_gameplay_active or not is_valid or cell.x < 0 or cell.x >= grid_size.x or cell.y < 0 or cell.y >= grid_size.y:
		_cursor_3d.visible = false
		return

	_cursor_3d.visible = true
	_cursor_3d.position = GameConstants.grid_to_world(cell, 0.08)
	if cell == Vector2i.ZERO and active_view_floor == 0:
		_cursor_mat.albedo_color = Color(1.0, 0.45, 0.25)
		_cursor_mat.emission = Color(0.95, 0.35, 0.15)
	else:
		_cursor_mat.albedo_color = Color(0.25, 0.95, 1.0)
		_cursor_mat.emission = Color(0.20, 0.85, 1.0)
