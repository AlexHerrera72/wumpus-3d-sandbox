class_name PathVisualizer3D
extends Node3D
## Entorno Visual 3D: PathVisualizer3D
## Traza en 3D la ruta activa de AStarGrid2D correspondiente a su piso asignado
## utilizando ImmediateMesh, omitiendo saltos entre pisos o saltos de portal.

var assigned_floor: int = 0

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _line_material: StandardMaterial3D

func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh

	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.albedo_color = Color(0.20, 0.95, 1.0)
	_line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance.material_override = _line_material
	add_child(_mesh_instance)

	EventBus.epistemic_multifloor_updated.connect(_on_epistemic_multifloor_updated)

func set_dimmed(dimmed: bool) -> void:
	if _line_material != null:
		_line_material.albedo_color = Color(0.08, 0.36, 0.42) if dimmed else Color(0.20, 0.95, 1.0)

func _on_epistemic_multifloor_updated(_visual_states_3d: Dictionary, current_path_3d: Array[Vector3i]) -> void:
	draw_active_path_3d(current_path_3d)

func draw_active_path_3d(grid_path: Array[Vector3i]) -> void:
	if _immediate_mesh == null:
		return
	_immediate_mesh.clear_surfaces()
	if grid_path.size() < 2:
		return

	var ribbon_half_width: float = 0.11
	var y_height: float = 0.14
	var has_segments: bool = false

	for i: int in range(grid_path.size() - 1):
		var c_start: Vector3i = grid_path[i]
		var c_end: Vector3i = grid_path[i + 1]
		if c_start.z != assigned_floor or c_end.z != assigned_floor:
			continue
		var manhattan: int = absi(c_end.x - c_start.x) + absi(c_end.y - c_start.y)
		if manhattan != 1:
			# Salto de teletransporte por portal en el mismo piso: no dibujamos linea recta cruzando muros
			continue

		if not has_segments:
			_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			has_segments = true

		var p_start: Vector3 = GameConstants.grid3_to_world(c_start, y_height)
		var p_end: Vector3 = GameConstants.grid3_to_world(c_end, y_height)
		var seg_dir: Vector3 = (p_end - p_start).normalized()
		var perp: Vector3 = Vector3(-seg_dir.z, 0.0, seg_dir.x) * ribbon_half_width

		var v0: Vector3 = p_start + perp
		var v1: Vector3 = p_start - perp
		var v2: Vector3 = p_end + perp
		var v3: Vector3 = p_end - perp

		_immediate_mesh.surface_set_normal(Vector3.UP)
		_immediate_mesh.surface_add_vertex(v0)
		_immediate_mesh.surface_add_vertex(v2)
		_immediate_mesh.surface_add_vertex(v1)

		_immediate_mesh.surface_set_normal(Vector3.UP)
		_immediate_mesh.surface_add_vertex(v1)
		_immediate_mesh.surface_add_vertex(v2)
		_immediate_mesh.surface_add_vertex(v3)

	if has_segments:
		_immediate_mesh.surface_end()
