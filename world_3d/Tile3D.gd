class_name Tile3D
extends Node3D
## Entorno Visual 3D: Tile3D
## Baldosa 3D auto-contenida generada proceduralmente (cero dependencias externas).
## Muestra colores epistemicos XAI dinamicos y los indicadores 3D de Pozo, Wumpus,
## Muro, Lingote de Oro, Brisa y Hedor, incluyendo animacion de colocacion vertical
## estilo pieza de ajedrez (Y = +1.6 -> Y = base en 0.28s TRANS_BACK / EASE_OUT).

const COLOR_UNKNOWN: Color = Color(0.28, 0.30, 0.35)
const COLOR_SAFE: Color = Color(0.18, 0.75, 0.45)
const COLOR_VISITED_SAFE: Color = Color(0.15, 0.55, 0.50)
const COLOR_SUSPICIOUS: Color = Color(0.95, 0.75, 0.15)
const COLOR_HAZARD_OR_WALL: Color = Color(0.85, 0.22, 0.22)

const DROP_OFFSET_Y: float = 1.6
const DROP_DURATION_SEC: float = 0.28

var grid_coords: Vector2i = Vector2i.ZERO

var _base_mesh: MeshInstance3D
var _base_material: StandardMaterial3D
var _origin_marker: MeshInstance3D

var _pit_node: Node3D
var _wumpus_node: Node3D
var _wumpus_body_mat: StandardMaterial3D
var _wall_node: MeshInstance3D
var _gold_node: Node3D
var _gold_mesh: MeshInstance3D
var _breeze_ring: MeshInstance3D
var _stench_ring: MeshInstance3D
var _coord_label: Label3D

var _anim_time: float = 0.0
var _had_wumpus: bool = false
var _had_wall: bool = false
var _had_gold: bool = false
var _is_first_truth_sync: bool = true

func setup_tile(coords: Vector2i) -> void:
	grid_coords = coords
	position = GameConstants.grid_to_world(coords, 0.0)
	_build_procedural_geometry()
	set_visual_belief_state(GameConstants.CellVisualState.UNKNOWN)

func _process(delta: float) -> void:
	_anim_time += delta
	if _gold_node != null and _gold_node.visible and _gold_mesh != null:
		_gold_mesh.rotation.y = _anim_time * 1.8
		_gold_mesh.position.y = sin(_anim_time * 3.0) * 0.05
	if _breeze_ring != null and _breeze_ring.visible:
		_breeze_ring.rotation.y = _anim_time * 1.2
	if _stench_ring != null and _stench_ring.visible:
		_stench_ring.rotation.y = -_anim_time * 1.5

func _build_procedural_geometry() -> void:
	# 1. Baldosa base (BoxMesh de 1.85 x 0.2 x 1.85 segun Seccion 5.3)
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

	# Etiqueta discreta de coordenada en esquina de la baldosa
	_coord_label = Label3D.new()
	_coord_label.text = "(%d,%d)" % [grid_coords.x, grid_coords.y]
	_coord_label.font_size = 22
	_coord_label.pixel_size = 0.008
	_coord_label.position = Vector3(-0.62, 0.015, 0.68)
	_coord_label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_coord_label.modulate = Color(0.92, 0.94, 0.98, 0.78)
	_coord_label.outline_size = 4
	add_child(_coord_label)

	# Marcador especial de extraccion si es (0, 0)
	if grid_coords == Vector2i.ZERO:
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

	# 2. Prop: Pozo (CylinderMesh negro profundo + anillo azulado)
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
	var pit_mat: StandardMaterial3D = StandardMaterial3D.new()
	pit_mat.albedo_color = Color(0.02, 0.02, 0.04)
	pit_mat.roughness = 1.0
	pit_well.material_override = pit_mat
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

	# 3. Prop: Wumpus (CapsuleMesh + cuernos PrismMesh purpura/rojo)
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

	# 4. Prop: Muro (BoxMesh gris piedra elevado 1.8 x 1.4 x 1.8 segun Seccion 5.3)
	_wall_node = MeshInstance3D.new()
	var wall_box: BoxMesh = BoxMesh.new()
	wall_box.size = Vector3(1.8, 1.4, 1.8)
	_wall_node.mesh = wall_box
	_wall_node.position = Vector3(0.0, 0.7, 0.0)
	var wall_mat: StandardMaterial3D = StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.45, 0.47, 0.52)
	wall_mat.roughness = 0.85
	_wall_node.material_override = wall_mat
	_wall_node.visible = false
	add_child(_wall_node)

	# 5. Prop: Lingote de Oro (PrismMesh dorado brillante con emision)
	_gold_node = Node3D.new()
	_gold_node.position = Vector3(0.0, 0.38, 0.0)
	_gold_node.visible = false
	add_child(_gold_node)

	_gold_mesh = MeshInstance3D.new()
	var gold_prism: PrismMesh = PrismMesh.new()
	gold_prism.size = Vector3(0.75, 0.42, 0.48)
	_gold_mesh.mesh = gold_prism
	var gold_mat: StandardMaterial3D = StandardMaterial3D.new()
	gold_mat.albedo_color = Color(1.0, 0.84, 0.15)
	gold_mat.metallic = 0.85
	gold_mat.roughness = 0.2
	gold_mat.emission_enabled = true
	gold_mat.emission = Color(0.95, 0.72, 0.10)
	gold_mat.emission_energy_multiplier = 1.25
	_gold_mesh.material_override = gold_mat
	_gold_node.add_child(_gold_mesh)

	# 6. Indicadores sensoriales de Brisa (anillo celeste) y Hedor (anillo purpura/ambar)
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

func set_visual_belief_state(vis_state: GameConstants.CellVisualState) -> void:
	if _base_material == null:
		return
	match vis_state:
		GameConstants.CellVisualState.UNKNOWN:
			_base_material.albedo_color = COLOR_UNKNOWN
		GameConstants.CellVisualState.SAFE:
			_base_material.albedo_color = COLOR_SAFE
		GameConstants.CellVisualState.VISITED_SAFE:
			_base_material.albedo_color = COLOR_VISITED_SAFE
		GameConstants.CellVisualState.SUSPICIOUS:
			_base_material.albedo_color = COLOR_SUSPICIOUS
		GameConstants.CellVisualState.HAZARD_OR_WALL:
			_base_material.albedo_color = COLOR_HAZARD_OR_WALL

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
	has_breeze: bool,
	has_stench: bool
) -> void:
	_pit_node.visible = has_pit
	_wall_node.visible = has_wall
	_gold_node.visible = has_gold

	if not _is_first_truth_sync:
		if has_wall and not _had_wall:
			_animate_chess_piece_drop(_wall_node, 0.7)
		if has_gold and not _had_gold:
			_animate_chess_piece_drop(_gold_node, 0.38)
		if has_wumpus_here and wumpus_alive and not _had_wumpus:
			_animate_chess_piece_drop(_wumpus_node, 0.0)

	if has_wumpus_here:
		_wumpus_node.visible = true
		if wumpus_alive:
			_wumpus_node.rotation_degrees = Vector3.ZERO
			if _is_first_truth_sync or _had_wumpus:
				_wumpus_node.position = Vector3.ZERO
			_wumpus_body_mat.albedo_color = Color(0.62, 0.14, 0.42)
		else:
			# Wumpus abatido por la flecha
			_wumpus_node.rotation_degrees = Vector3(0.0, 0.0, 82.0)
			_wumpus_node.position = Vector3(0.0, -0.22, 0.0)
			_wumpus_body_mat.albedo_color = Color(0.32, 0.28, 0.34)
	else:
		_wumpus_node.visible = false

	_breeze_ring.visible = has_breeze and (not has_wall) and (not has_pit)
	_stench_ring.visible = has_stench and (not has_wall) and (not has_pit)

	_had_wumpus = has_wumpus_here and wumpus_alive
	_had_wall = has_wall
	_had_gold = has_gold
	_is_first_truth_sync = false
