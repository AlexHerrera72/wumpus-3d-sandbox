class_name AgentVisual3D
extends Node3D
## Entorno Visual 3D: AgentVisual3D
## Representacion 3D procedural del Agente Explorador con Coreografia de Movimiento
## Estilo Pieza de Ajedrez (4 sub-etapas) + Animacion de Teletransporte por Portal.

const ORIENT_DURATION_BASE: float = 0.18
const ARC_GLIDE_DURATION_BASE: float = 0.55
const LAND_BOUNCE_DURATION_BASE: float = 0.12
const TILT_MAX_RAD: float = deg_to_rad(-12.0)

var _pivot: Node3D
var _move_tween: Tween
var _arrow_mesh: MeshInstance3D
var _arc_start_pos: Vector3 = Vector3.ZERO
var _arc_end_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	_build_agent_mesh()
	EventBus.agent_transform_3d_updated.connect(_on_agent_transform_3d_updated)
	EventBus.agent_teleported.connect(_on_agent_teleported)
	EventBus.agent_arrow_fired_3d.connect(_on_agent_arrow_fired_3d)

func _build_agent_mesh() -> void:
	_pivot = Node3D.new()
	_pivot.name = "ChessPiecePivot"
	add_child(_pivot)

	# Peana / Base cilindrica estilo pieza de ajedrez clasica
	var base_inst: MeshInstance3D = MeshInstance3D.new()
	var base_cyl: CylinderMesh = CylinderMesh.new()
	base_cyl.top_radius = 0.42
	base_cyl.bottom_radius = 0.50
	base_cyl.height = 0.14
	base_inst.mesh = base_cyl
	base_inst.position = Vector3(0.0, 0.07, 0.0)
	var base_mat: StandardMaterial3D = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.16, 0.20, 0.28)
	base_mat.metallic = 0.35
	base_mat.roughness = 0.30
	base_inst.material_override = base_mat
	_pivot.add_child(base_inst)

	# Cuerpo principal CapsuleMesh azul/blanco
	var body_inst: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.12
	body_inst.mesh = capsule
	body_inst.position = Vector3(0.0, 0.62, 0.0)

	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.18, 0.52, 0.92)
	body_mat.metallic = 0.25
	body_mat.roughness = 0.32
	body_inst.material_override = body_mat
	_pivot.add_child(body_inst)

	# Visor frontal blanco/cian que indica facing_dir
	var visor_inst: MeshInstance3D = MeshInstance3D.new()
	var visor_box: BoxMesh = BoxMesh.new()
	visor_box.size = Vector3(0.46, 0.18, 0.24)
	visor_inst.mesh = visor_box
	visor_inst.position = Vector3(0.0, 0.86, 0.28)

	var visor_mat: StandardMaterial3D = StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.88, 0.97, 1.0)
	visor_mat.emission_enabled = true
	visor_mat.emission = Color(0.35, 0.85, 1.0)
	visor_mat.emission_energy_multiplier = 1.1
	visor_inst.material_override = visor_mat
	_pivot.add_child(visor_inst)

	# Mochila de sensores XAI
	var pack_inst: MeshInstance3D = MeshInstance3D.new()
	var pack_box: BoxMesh = BoxMesh.new()
	pack_box.size = Vector3(0.40, 0.45, 0.22)
	pack_inst.mesh = pack_box
	pack_inst.position = Vector3(0.0, 0.66, -0.32)
	var pack_mat: StandardMaterial3D = StandardMaterial3D.new()
	pack_mat.albedo_color = Color(0.92, 0.94, 0.98)
	pack_mat.roughness = 0.4
	pack_inst.material_override = pack_mat
	_pivot.add_child(pack_inst)

	# Proyectil de flecha energetica
	_arrow_mesh = MeshInstance3D.new()
	var arrow_box: BoxMesh = BoxMesh.new()
	arrow_box.size = Vector3(0.10, 0.10, 0.85)
	_arrow_mesh.mesh = arrow_box
	var arrow_mat: StandardMaterial3D = StandardMaterial3D.new()
	arrow_mat.albedo_color = Color(1.0, 0.92, 0.25)
	arrow_mat.emission_enabled = true
	arrow_mat.emission = Color(1.0, 0.80, 0.15)
	arrow_mat.emission_energy_multiplier = 2.0
	_arrow_mesh.material_override = arrow_mat
	_arrow_mesh.visible = false
	add_child(_arrow_mesh)

func _on_agent_transform_3d_updated(grid_pos: Vector3i, facing_dir: Vector2i, is_moving: bool) -> void:
	var target_local: Vector3 = GameConstants.grid3_to_world(grid_pos, 0.0)
	var target_yaw: float = _dir_to_yaw(facing_dir)

	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	if not is_moving:
		position = target_local
		scale = Vector3.ONE
		if _pivot != null:
			_pivot.rotation = Vector3(0.0, target_yaw, 0.0)
			_pivot.scale = Vector3.ONE
		return

	var speed_mult: float = clampf(GameConstants.current_speed_multiplier, 0.25, 4.0)
	var orient_dur: float = ORIENT_DURATION_BASE / speed_mult
	var glide_dur: float = ARC_GLIDE_DURATION_BASE / speed_mult
	var bounce_dur: float = LAND_BOUNCE_DURATION_BASE / speed_mult

	_arc_start_pos = Vector3(position.x, 0.0, position.z)
	_arc_end_pos = target_local

	var current_yaw: float = _pivot.rotation.y if _pivot != null else 0.0
	var shortest_target_yaw: float = current_yaw + angle_difference(current_yaw, target_yaw)

	_move_tween = create_tween()

	if _pivot != null:
		_move_tween.tween_property(_pivot, "rotation:y", shortest_target_yaw, orient_dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	_move_tween.tween_method(_update_chess_parabolic_arc, 0.0, 1.0, glide_dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	_move_tween.tween_callback(_apply_landing_compression)
	if _pivot != null:
		_move_tween.tween_property(_pivot, "scale", Vector3.ONE, bounce_dur).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _on_agent_teleported(_from_cell: Vector3i, to_cell: Vector3i) -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	var speed_mult: float = clampf(GameConstants.current_speed_multiplier, 0.25, 4.0)
	var shrink_dur: float = 0.34 / speed_mult
	var emerge_dur: float = 0.40 / speed_mult
	var dest_local: Vector3 = GameConstants.grid3_to_world(to_cell, 0.0)

	_move_tween = create_tween()
	if _pivot != null:
		_move_tween.set_parallel(true)
		_move_tween.tween_property(_pivot, "scale", Vector3(0.08, 1.65, 0.08), shrink_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_move_tween.tween_property(_pivot, "rotation:y", _pivot.rotation.y + TAU, shrink_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_move_tween.set_parallel(false)

	_move_tween.tween_callback(func() -> void:
		position = dest_local
		if _pivot != null:
			_pivot.rotation.x = 0.0
			_pivot.scale = Vector3(0.08, 1.65, 0.08)
	)

	if _pivot != null:
		_move_tween.tween_property(_pivot, "scale", Vector3.ONE, emerge_dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _update_chess_parabolic_arc(t: float) -> void:
	var horiz: Vector3 = _arc_start_pos.lerp(_arc_end_pos, t)
	var arc_y: float = 4.0 * GameConstants.CHESS_ARC_HEIGHT * t * (1.0 - t)
	position = Vector3(horiz.x, arc_y, horiz.z)

	if _pivot != null:
		var tilt_envelope: float = sin(t * PI)
		_pivot.rotation.x = TILT_MAX_RAD * tilt_envelope

func _apply_landing_compression() -> void:
	position = _arc_end_pos
	if _pivot != null:
		_pivot.rotation.x = 0.0
		_pivot.scale = Vector3(1.06, 0.92, 1.06)

func _on_agent_arrow_fired_3d(from_cell: Vector3i, target_cell: Vector3i, _hit_wumpus: bool) -> void:
	if _arrow_mesh == null:
		return
	var start_local: Vector3 = GameConstants.grid3_to_world(from_cell, 0.65)
	var end_local: Vector3 = GameConstants.grid3_to_world(target_cell, 0.65)
	var shoot_dir: Vector2i = Vector2i(signi(target_cell.x - from_cell.x), signi(target_cell.y - from_cell.y))

	_arrow_mesh.top_level = false
	_arrow_mesh.position = start_local - position
	_arrow_mesh.rotation = Vector3(0.0, _dir_to_yaw(shoot_dir), 0.0)
	_arrow_mesh.visible = true

	var arrow_tween: Tween = create_tween()
	arrow_tween.tween_property(_arrow_mesh, "position", end_local - position, 0.28).set_trans(Tween.TRANS_LINEAR)
	arrow_tween.tween_callback(func() -> void: _arrow_mesh.visible = false)

func _dir_to_yaw(dir: Vector2i) -> float:
	if dir == Vector2i(1, 0):
		return PI * 0.5
	elif dir == Vector2i(-1, 0):
		return -PI * 0.5
	elif dir == Vector2i(0, -1):
		return PI
	return 0.0
