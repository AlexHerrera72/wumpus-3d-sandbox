class_name Tile3D
extends Node3D
## Entorno Visual 3D: Tile3D
## Baldosa 3D auto-contenida con soporte de transparencia real (TRANSPARENCY_ALPHA)
## para ver limpiamente a traves de pisos superiores al trabajar en pisos inferiores,
## ademas de Portales Azul/Naranja, Escaleras 3D libres y Flechas recogibles.

const COLOR_UNKNOWN: Color = Color(0.28, 0.30, 0.35)
const COLOR_SAFE: Color = Color(0.18, 0.75, 0.45)
const COLOR_VISITED_SAFE: Color = Color(0.15, 0.55, 0.50)
const COLOR_SUSPICIOUS: Color = Color(0.95, 0.75, 0.15)
const COLOR_HAZARD_OR_WALL: Color = Color(0.85, 0.22, 0.22)

const PORTAL_BLUE_OUTER: Color = Color(0.12, 0.56, 1.0)
const PORTAL_BLUE_INNER: Color = Color(0.38, 0.80, 1.0, 0.85)
const PORTAL_ORANGE_OUTER: Color = Color(1.0, 0.46, 0.08)
const PORTAL_ORANGE_INNER: Color = Color(1.0, 0.72, 0.28, 0.85)

const DROP_OFFSET_Y: float = 1.6
const DROP_DURATION_SEC: float = 0.28

var grid_coords: Vector3i = Vector3i.ZERO

var _base_mesh: MeshInstance3D
var _base_material: StandardMaterial3D
var _origin_marker: MeshInstance3D

var _pit_node: Node3D
var _pit_mat: StandardMaterial3D
var _wumpus_node: Node3D
var _wumpus_body_mat: StandardMaterial3D
var _wall_node: MeshInstance3D
var _wall_mat: StandardMaterial3D
var _gold_node: Node3D
var _gold_mesh: MeshInstance3D
var _gold_mat: StandardMaterial3D

var _portal_node: Node3D
var _portal_outer_ring: MeshInstance3D
var _portal_inner_ring: MeshInstance3D
var _portal_outer_mat: StandardMaterial3D
var _portal_inner_mat: StandardMaterial3D
var _portal_is_pending: bool = false

var _stairs_node: Node3D
var _stair_mat: StandardMaterial3D
var _rail_mat: StandardMaterial3D
var _stairs_label: Label3D
var _stairs_is_pending: bool = false

var _arrow_pickup_node: Node3D
var _arrow_pickup_pivot: Node3D

var _breeze_ring: MeshInstance3D
var _stench_ring: MeshInstance3D
var _coord_label: Label3D

var _anim_time: float = 0.0
var _current_vis_state: GameConstants.CellVisualState = GameConstants.CellVisualState.UNKNOWN
var _floor_vis_mode: String = "ACTIVE" # "ACTIVE", "ABOVE", "BELOW"
var _had_wumpus: bool = false
var _had_wall: bool = false
var _had_gold: bool = false
var _had_portal: bool = false
var _had_stairs: bool = false
var _had_arrow: bool = false
var _is_first_truth_sync: bool = true

func setup_tile(coords: Vector3i) -> void:
	grid_coords = coords
	position = GameConstants.grid3_to_world(coords, 0.0)
	_build_procedural_geometry()
	set_visual_belief_state(GameConstants.CellVisualState.UNKNOWN)

func _process(delta: float) -> void:
	_anim_time += delta
	if _gold_node != null and _gold_node.visible and _gold_mesh != null:
		_gold_mesh.rotation.y = _anim_time * 1.8
		_gold_mesh.position.y = sin(_anim_time * 3.0) * 0.05
	if _arrow_pickup_node != null and _arrow_pickup_node.visible and _arrow_pickup_pivot != null:
		_arrow_pickup_pivot.rotation.y = _anim_time * 2.2
		_arrow_pickup_pivot.position.y = 0.48 + sin(_anim_time * 3.5) * 0.06
	if _portal_node != null and _portal_node.visible:
		if _portal_outer_ring != null:
			_portal_outer_ring.rotation.y = _anim_time * 1.6
		if _portal_inner_ring != null:
			_portal_inner_ring.rotation.y = -_anim_time * 2.8
			_portal_inner_ring.position.y = 0.14 + sin(_anim_time * 4.0) * 0.03
		if _portal_is_pending and _portal_outer_mat != null:
			_portal_outer_mat.emission_energy_multiplier = 0.7 + 0.8 * absf(sin(_anim_time * 4.5))
	if _stairs_node != null and _stairs_node.visible and _stairs_is_pending and _stair_mat != null:
		_stair_mat.emission_energy_multiplier = 0.35 + 0.55 * absf(sin(_anim_time * 4.5))
	if _breeze_ring != null and _breeze_ring.visible:
		_breeze_ring.rotation.y = _anim_time * 1.2
	if _stench_ring != null and _stench_ring.visible:
		_stench_ring.rotation.y = -_anim_time * 1.5

func _build_procedural_geometry() -> void:
	# 1. Baldosa base
	_base_mesh = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.85, 0.2, 1.85)
	_base_mesh.mesh = box
	_base_mesh.position = Vector3(0.0, -0.1, 0.0)

	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = COLOR_UNKNOWN
	_base_material.roughness = 0.65
	_base_material.metallic = 0.08
	_base_mesh.material_override = _base_material
	add_child(_base_mesh)

	_coord_label = Label3D.new()
	_coord_label.text = "(%d,%d)" % [grid_coords.x, grid_coords.y]
	_coord_label.font_size = 22
	_coord_label.pixel_size = 0.008
	_coord_label.position = Vector3(-0.62, 0.015, 0.68)
	_coord_label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_coord_label.modulate = Color(0.92, 0.94, 0.98, 0.78)
	_coord_label.outline_size = 4
	add_child(_coord_label)

	if grid_coords == Vector3i(0, 0, 0):
		_origin_marker = MeshInstance3D.new()
		var home_torus: TorusMesh = TorusMesh.new()
		home_torus.inner_radius = 0.62
		home_torus.outer_radius = 0.75
		_origin_marker.mesh = home_torus
		_origin_marker.position = Vector3(0.0, 0.02, 0.0)
		var home_mat: StandardMaterial3D = StandardMaterial3D.new()
		home_mat.albedo_color = Color(0.25, 0.85, 1.0)
		home_mat.emission_enabled = true
		home_mat.emission = Color(0.15, 0.65, 0.95)
		home_mat.emission_energy_multiplier = 0.9
		_origin_marker.material_override = home_mat
		add_child(_origin_marker)

	# 2. Prop: Pozo
	_pit_node = Node3D.new()
	_pit_node.visible = false
	add_child(_pit_node)

	var pit_well: MeshInstance3D = MeshInstance3D.new()
	var pit_cyl: CylinderMesh = CylinderMesh.new()
	pit_cyl.top_radius = 0.64
	pit_cyl.bottom_radius = 0.52
	pit_cyl.height = 0.24
	pit_well.mesh = pit_cyl
	pit_well.position = Vector3(0.0, -0.06, 0.0)
	_pit_mat = StandardMaterial3D.new()
	_pit_mat.albedo_color = Color(0.02, 0.02, 0.04)
	_pit_mat.roughness = 1.0
	pit_well.material_override = _pit_mat
	_pit_node.add_child(pit_well)

	var pit_rim: MeshInstance3D = MeshInstance3D.new()
	var rim_torus: TorusMesh = TorusMesh.new()
	rim_torus.inner_radius = 0.58
	rim_torus.outer_radius = 0.72
	pit_rim.mesh = rim_torus
	pit_rim.position = Vector3(0.0, 0.04, 0.0)
	var rim_mat: StandardMaterial3D = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.22, 0.65, 0.95)
	rim_mat.emission_enabled = true
	rim_mat.emission = Color(0.15, 0.50, 0.85)
	rim_mat.emission_energy_multiplier = 0.8
	pit_rim.material_override = rim_mat
	_pit_node.add_child(pit_rim)

	# 3. Prop: Wumpus
	_wumpus_node = Node3D.new()
	_wumpus_node.visible = false
	add_child(_wumpus_node)

	var wumpus_body: MeshInstance3D = MeshInstance3D.new()
	var w_cap: CapsuleMesh = CapsuleMesh.new()
	w_cap.radius = 0.44
	w_cap.height = 1.15
	wumpus_body.mesh = w_cap
	wumpus_body.position = Vector3(0.0, 0.58, 0.0)
	_wumpus_body_mat = StandardMaterial3D.new()
	_wumpus_body_mat.albedo_color = Color(0.62, 0.14, 0.42)
	_wumpus_body_mat.roughness = 0.45
	wumpus_body.material_override = _wumpus_body_mat
	_wumpus_node.add_child(wumpus_body)

	var horn_mat: StandardMaterial3D = StandardMaterial3D.new()
	horn_mat.albedo_color = Color(0.95, 0.25, 0.20)
	horn_mat.emission_enabled = true
	horn_mat.emission = Color(0.85, 0.15, 0.15)
	horn_mat.emission_energy_multiplier = 0.6

	for side: float in [-1.0, 1.0]:
		var horn: MeshInstance3D = MeshInstance3D.new()
		var prism: PrismMesh = PrismMesh.new()
		prism.size = Vector3(0.22, 0.36, 0.22)
		horn.mesh = prism
		horn.position = Vector3(side * 0.28, 1.12, 0.0)
		horn.rotation_degrees = Vector3(0.0, 0.0, -side * 18.0)
		horn.material_override = horn_mat
		_wumpus_node.add_child(horn)

	# 4. Prop: Muro
	_wall_node = MeshInstance3D.new()
	var wall_box: BoxMesh = BoxMesh.new()
	wall_box.size = Vector3(1.8, 1.4, 1.8)
	_wall_node.mesh = wall_box
	_wall_node.position = Vector3(0.0, 0.7, 0.0)
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color(0.45, 0.47, 0.52)
	_wall_mat.roughness = 0.85
	_wall_node.material_override = _wall_mat
	_wall_node.visible = false
	add_child(_wall_node)

	# 5. Prop: Lingote de Oro
	_gold_node = Node3D.new()
	_gold_node.position = Vector3(0.0, 0.38, 0.0)
	_gold_node.visible = false
	add_child(_gold_node)

	_gold_mesh = MeshInstance3D.new()
	var gold_prism: PrismMesh = PrismMesh.new()
	gold_prism.size = Vector3(0.75, 0.42, 0.48)
	_gold_mesh.mesh = gold_prism
	_gold_mat = StandardMaterial3D.new()
	_gold_mat.albedo_color = Color(1.0, 0.84, 0.15)
	_gold_mat.metallic = 0.85
	_gold_mat.roughness = 0.2
	_gold_mat.emission_enabled = true
	_gold_mat.emission = Color(0.95, 0.72, 0.10)
	_gold_mat.emission_energy_multiplier = 1.25
	_gold_mesh.material_override = _gold_mat
	_gold_node.add_child(_gold_mesh)

	# 6. Prop: Portal Estilo Portal (AZUL / NARANJA)
	_portal_node = Node3D.new()
	_portal_node.visible = false
	add_child(_portal_node)

	_portal_outer_ring = MeshInstance3D.new()
	var p_torus_out: TorusMesh = TorusMesh.new()
	p_torus_out.inner_radius = 0.54
	p_torus_out.outer_radius = 0.74
	_portal_outer_ring.mesh = p_torus_out
	_portal_outer_ring.position = Vector3(0.0, 0.09, 0.0)
	_portal_outer_mat = StandardMaterial3D.new()
	_portal_outer_mat.albedo_color = PORTAL_BLUE_OUTER
	_portal_outer_mat.emission_enabled = true
	_portal_outer_mat.emission = PORTAL_BLUE_OUTER
	_portal_outer_mat.emission_energy_multiplier = 1.4
	_portal_outer_ring.material_override = _portal_outer_mat
	_portal_node.add_child(_portal_outer_ring)

	_portal_inner_ring = MeshInstance3D.new()
	var p_cyl: CylinderMesh = CylinderMesh.new()
	p_cyl.top_radius = 0.50
	p_cyl.bottom_radius = 0.36
	p_cyl.height = 0.06
	_portal_inner_ring.mesh = p_cyl
	_portal_inner_ring.position = Vector3(0.0, 0.14, 0.0)
	_portal_inner_mat = StandardMaterial3D.new()
	_portal_inner_mat.albedo_color = PORTAL_BLUE_INNER
	_portal_inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_portal_inner_mat.emission_enabled = true
	_portal_inner_mat.emission = PORTAL_BLUE_OUTER
	_portal_inner_mat.emission_energy_multiplier = 1.0
	_portal_inner_ring.material_override = _portal_inner_mat
	_portal_node.add_child(_portal_inner_ring)

	# 7. Prop: Escalera 3D de Peldanos
	_stairs_node = Node3D.new()
	_stairs_node.visible = false
	add_child(_stairs_node)

	_stair_mat = StandardMaterial3D.new()
	_stair_mat.albedo_color = Color(0.68, 0.54, 0.36)
	_stair_mat.roughness = 0.75
	_stair_mat.emission = Color(0.85, 0.68, 0.25)

	_rail_mat = StandardMaterial3D.new()
	_rail_mat.albedo_color = Color(0.35, 0.27, 0.18)
	_rail_mat.roughness = 0.8

	for step_i: int in range(4):
		var step_mesh: MeshInstance3D = MeshInstance3D.new()
		var s_box: BoxMesh = BoxMesh.new()
		var h: float = 0.18 * float(step_i + 1)
		s_box.size = Vector3(1.10, h, 0.30)
		step_mesh.mesh = s_box
		step_mesh.position = Vector3(0.0, h * 0.5, 0.45 - float(step_i) * 0.30)
		step_mesh.material_override = _stair_mat
		_stairs_node.add_child(step_mesh)

	for side_x: float in [-0.58, 0.58]:
		var rail: MeshInstance3D = MeshInstance3D.new()
		var r_box: BoxMesh = BoxMesh.new()
		r_box.size = Vector3(0.08, 0.12, 1.38)
		rail.mesh = r_box
		rail.position = Vector3(side_x, 0.56, 0.0)
		rail.rotation_degrees = Vector3(26.0, 0.0, 0.0)
		rail.material_override = _rail_mat
		_stairs_node.add_child(rail)

	_stairs_label = Label3D.new()
	_stairs_label.text = "▲"
	_stairs_label.font_size = 44
	_stairs_label.pixel_size = 0.008
	_stairs_label.position = Vector3(0.0, 1.05, 0.0)
	_stairs_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_stairs_label.modulate = Color(0.98, 0.90, 0.45)
	_stairs_label.outline_size = 6
	_stairs_node.add_child(_stairs_label)

	# 8. Prop: Flecha Recogible 3D
	_arrow_pickup_node = Node3D.new()
	_arrow_pickup_node.visible = false
	add_child(_arrow_pickup_node)

	_arrow_pickup_pivot = Node3D.new()
	_arrow_pickup_pivot.position = Vector3(0.0, 0.48, 0.0)
	_arrow_pickup_node.add_child(_arrow_pickup_pivot)

	var shaft: MeshInstance3D = MeshInstance3D.new()
	var shaft_cyl: CylinderMesh = CylinderMesh.new()
	shaft_cyl.top_radius = 0.045
	shaft_cyl.bottom_radius = 0.045
	shaft_cyl.height = 0.95
	shaft.mesh = shaft_cyl
	shaft.rotation_degrees = Vector3(0.0, 0.0, 45.0)
	var shaft_mat: StandardMaterial3D = StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(0.95, 0.85, 0.42)
	shaft_mat.metallic = 0.6
	shaft_mat.emission_enabled = true
	shaft_mat.emission = Color(0.85, 0.68, 0.18)
	shaft_mat.emission_energy_multiplier = 0.8
	shaft.material_override = shaft_mat
	_arrow_pickup_pivot.add_child(shaft)

	var tip: MeshInstance3D = MeshInstance3D.new()
	var tip_prism: PrismMesh = PrismMesh.new()
	tip_prism.size = Vector3(0.24, 0.28, 0.14)
	tip.mesh = tip_prism
	tip.position = Vector3(-0.36, 0.36, 0.0)
	tip.rotation_degrees = Vector3(0.0, 0.0, 45.0)
	var tip_mat: StandardMaterial3D = StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.92, 0.96, 1.0)
	tip_mat.metallic = 0.9
	tip_mat.emission_enabled = true
	tip_mat.emission = Color(0.45, 0.85, 1.0)
	tip_mat.emission_energy_multiplier = 1.1
	tip.material_override = tip_mat
	_arrow_pickup_pivot.add_child(tip)

	# 9. Anillos de Brisa y Hedor
	_breeze_ring = MeshInstance3D.new()
	var b_torus: TorusMesh = TorusMesh.new()
	b_torus.inner_radius = 0.46
	b_torus.outer_radius = 0.53
	_breeze_ring.mesh = b_torus
	_breeze_ring.position = Vector3(0.0, 0.05, 0.0)
	var b_mat: StandardMaterial3D = StandardMaterial3D.new()
	b_mat.albedo_color = Color(0.35, 0.82, 1.0, 0.85)
	b_mat.emission_enabled = true
	b_mat.emission = Color(0.25, 0.70, 0.95)
	b_mat.emission_energy_multiplier = 0.65
	_breeze_ring.material_override = b_mat
	_breeze_ring.visible = false
	add_child(_breeze_ring)

	_stench_ring = MeshInstance3D.new()
	var s_torus: TorusMesh = TorusMesh.new()
	s_torus.inner_radius = 0.32
	s_torus.outer_radius = 0.39
	_stench_ring.mesh = s_torus
	_stench_ring.position = Vector3(0.0, 0.08, 0.0)
	var s_mat: StandardMaterial3D = StandardMaterial3D.new()
	s_mat.albedo_color = Color(0.85, 0.30, 0.70, 0.85)
	s_mat.emission_enabled = true
	s_mat.emission = Color(0.75, 0.20, 0.55)
	s_mat.emission_energy_multiplier = 0.75
	_stench_ring.material_override = s_mat
	_stench_ring.visible = false
	add_child(_stench_ring)

func set_floor_visibility_mode(mode: String) -> void:
	## "ACTIVE": opaco 100% | "ABOVE": cristal muy transparente (ver a traves!) | "BELOW": oscurecido semitransparente
	_floor_vis_mode = mode
	var is_above: bool = (mode == "ABOVE")
	var is_below: bool = (mode == "BELOW")
	var alpha: float = 1.0
	var dark_mult: float = 1.0
	if is_above:
		alpha = 0.14
		dark_mult = 0.75
	elif is_below:
		alpha = 0.38
		dark_mult = 0.42

	_apply_base_color()
	_apply_mat_transparency(_wall_mat, Color(0.45, 0.47, 0.52), alpha, dark_mult)
	_apply_mat_transparency(_stair_mat, Color(0.68, 0.54, 0.36), alpha, dark_mult)
	_apply_mat_transparency(_rail_mat, Color(0.35, 0.27, 0.18), alpha, dark_mult)
	_apply_mat_transparency(_pit_mat, Color(0.02, 0.02, 0.04), alpha, 1.0)
	_apply_mat_transparency(_gold_mat, Color(1.0, 0.84, 0.15), clampf(alpha + 0.12, 0.0, 1.0), dark_mult)

	if _coord_label != null:
		_coord_label.visible = (mode == "ACTIVE")
	if _breeze_ring != null and is_above:
		_breeze_ring.visible = false
	if _stench_ring != null and is_above:
		_stench_ring.visible = false

func _apply_mat_transparency(mat: StandardMaterial3D, base_col: Color, alpha: float, dark_mult: float) -> void:
	if mat == null:
		return
	if alpha >= 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color = base_col
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(base_col.r * dark_mult, base_col.g * dark_mult, base_col.b * dark_mult, alpha)

func set_visual_belief_state(vis_state: GameConstants.CellVisualState) -> void:
	_current_vis_state = vis_state
	_apply_base_color()

func _apply_base_color() -> void:
	if _base_material == null:
		return
	var col: Color = COLOR_UNKNOWN
	match _current_vis_state:
		GameConstants.CellVisualState.UNKNOWN:
			col = COLOR_UNKNOWN
		GameConstants.CellVisualState.SAFE:
			col = COLOR_SAFE
		GameConstants.CellVisualState.VISITED_SAFE:
			col = COLOR_VISITED_SAFE
		GameConstants.CellVisualState.SUSPICIOUS:
			col = COLOR_SUSPICIOUS
		GameConstants.CellVisualState.HAZARD_OR_WALL:
			col = COLOR_HAZARD_OR_WALL

	if _floor_vis_mode == "ABOVE":
		_base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_base_material.albedo_color = Color(col.r * 0.8, col.g * 0.85, col.b * 0.95, 0.14)
	elif _floor_vis_mode == "BELOW":
		_base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_base_material.albedo_color = Color(col.r * 0.42, col.g * 0.42, col.b * 0.42, 0.40)
	else:
		_base_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_base_material.albedo_color = col

func _animate_chess_piece_drop(target_node: Node3D, rest_y: float) -> void:
	target_node.position.y = rest_y + DROP_OFFSET_Y
	var drop_tween: Tween = create_tween()
	drop_tween.tween_property(target_node, "position:y", rest_y, DROP_DURATION_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func update_truth_props(
	has_pit: bool,
	has_wumpus_here: bool,
	wumpus_alive: bool,
	has_wall: bool,
	has_gold: bool,
	portal_color: String,
	has_stairs_up: bool,
	has_stairs_down: bool,
	has_stairs_pending: bool,
	has_arrow_pickup: bool,
	has_breeze: bool,
	has_stench: bool
) -> void:
	var has_portal_here: bool = not portal_color.is_empty()
	var has_stairs_here: bool = has_stairs_up or has_stairs_down or has_stairs_pending
	_stairs_is_pending = has_stairs_pending

	_pit_node.visible = has_pit
	_wall_node.visible = has_wall
	_gold_node.visible = has_gold
	_portal_node.visible = has_portal_here
	_stairs_node.visible = has_stairs_here
	_arrow_pickup_node.visible = has_arrow_pickup

	if has_portal_here:
		_portal_is_pending = (portal_color == "blue_pending")
		if portal_color == "orange":
			_portal_outer_mat.albedo_color = PORTAL_ORANGE_OUTER
			_portal_outer_mat.emission = PORTAL_ORANGE_OUTER
			_portal_outer_mat.emission_energy_multiplier = 1.45
			_portal_inner_mat.albedo_color = PORTAL_ORANGE_INNER
			_portal_inner_mat.emission = PORTAL_ORANGE_OUTER
		else:
			_portal_outer_mat.albedo_color = PORTAL_BLUE_OUTER
			_portal_outer_mat.emission = PORTAL_BLUE_OUTER
			_portal_outer_mat.emission_energy_multiplier = 1.45
			_portal_inner_mat.albedo_color = PORTAL_BLUE_INNER
			_portal_inner_mat.emission = PORTAL_BLUE_OUTER

	if has_stairs_here and _stairs_label != null:
		_stair_mat.emission_enabled = has_stairs_pending
		if has_stairs_pending:
			_stairs_label.text = "?"
			_stairs_label.modulate = Color(1.0, 0.72, 0.20)
		elif has_stairs_up and has_stairs_down:
			_stairs_label.text = "▲▼"
			_stairs_label.modulate = Color(0.98, 0.90, 0.45)
		elif has_stairs_up:
			_stairs_label.text = "▲"
			_stairs_label.modulate = Color(0.98, 0.90, 0.45)
		else:
			_stairs_label.text = "▼"
			_stairs_label.modulate = Color(0.98, 0.90, 0.45)

	if not _is_first_truth_sync:
		if has_wall and not _had_wall:
			_animate_chess_piece_drop(_wall_node, 0.7)
		if has_gold and not _had_gold:
			_animate_chess_piece_drop(_gold_node, 0.38)
		if has_wumpus_here and wumpus_alive and not _had_wumpus:
			_animate_chess_piece_drop(_wumpus_node, 0.0)
		if has_portal_here and not _had_portal:
			_animate_chess_piece_drop(_portal_node, 0.0)
		if has_stairs_here and not _had_stairs:
			_animate_chess_piece_drop(_stairs_node, 0.0)
		if has_arrow_pickup and not _had_arrow:
			_animate_chess_piece_drop(_arrow_pickup_node, 0.0)

	if has_wumpus_here:
		_wumpus_node.visible = true
		if wumpus_alive:
			_wumpus_node.rotation_degrees = Vector3.ZERO
			if _is_first_truth_sync or _had_wumpus:
				_wumpus_node.position = Vector3.ZERO
			_wumpus_body_mat.albedo_color = Color(0.62, 0.14, 0.42)
		else:
			_wumpus_node.rotation_degrees = Vector3(0.0, 0.0, 82.0)
			_wumpus_node.position = Vector3(0.0, -0.22, 0.0)
			_wumpus_body_mat.albedo_color = Color(0.32, 0.28, 0.34)
	else:
		_wumpus_node.visible = false

	var show_sensory: bool = (_floor_vis_mode != "ABOVE")
	_breeze_ring.visible = show_sensory and has_breeze and (not has_wall) and (not has_pit)
	_stench_ring.visible = show_sensory and has_stench and (not has_wall) and (not has_pit)

	_had_wumpus = has_wumpus_here and wumpus_alive
	_had_wall = has_wall
	_had_gold = has_gold
	_had_portal = has_portal_here
	_had_stairs = has_stairs_here
	_had_arrow = has_arrow_pickup
	_is_first_truth_sync = false
