class_name PathVisualizer3D
extends Node3D
## Entorno Visual 3D: PathVisualizer3D
## Traza en 3D la ruta activa calculada por AStarGrid2D utilizando ImmediateMesh
## sin requerir recursos externos.

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

	EventBus.epistemic_state_updated.connect(_on_epistemic_state_updated)

func _on_epistemic_state_updated(_visual_states: Dictionary, current_path: Array[Vector2i]) -> void:
	draw_active_path(current_path)

func draw_active_path(grid_path: Array[Vector2i]) -> void:
	if _immediate_mesh == null:
		return
	_immediate_mesh.clear_surfaces()
	if grid_path.size() < 2:
		return

	var ribbon_half_width: float = 0.11
	var y_height: float = 0.14

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(grid_path.size() - 1):
		var p_start: Vector3 = GameConstants.grid_to_world(grid_path[i], y_height)
		var p_end: Vector3 = GameConstants.grid_to_world(grid_path[i + 1], y_height)
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

	_immediate_mesh.surface_end()
