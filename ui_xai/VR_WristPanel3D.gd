class_name VR_WristPanel3D
extends Node3D
## Interfaz XAI VR: VR_WristPanel3D
## Panel holografico 3D acoplado al controlador izquierdo (left_hand) en VR OpenXR.
## Renderiza en tiempo real la bitacora de inferencia XAI mediante un SubViewport
## proyectado sobre un QuadMesh.

var _sub_viewport: SubViewport
var _quad_mesh_instance: MeshInstance3D
var _status_label: Label
var _xai_rtl: RichTextLabel
var _vr_lines: Array[String] = []

func _ready() -> void:
	position = Vector3(0.06, 0.08, -0.05)
	rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	_build_wrist_viewport_and_mesh()

	EventBus.sim_state_changed.connect(_on_sim_state_changed)
	EventBus.xai_rule_triggered.connect(_on_xai_rule_triggered)
	EventBus.xai_cbr_triggered.connect(_on_xai_cbr_triggered)

func _build_wrist_viewport_and_mesh() -> void:
	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "WristSubViewport"
	_sub_viewport.size = Vector2i(520, 340)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.transparent_bg = false
	add_child(_sub_viewport)

	var bg_panel: PanelContainer = PanelContainer.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.071, 0.071, 0.082, 0.98)
	sb.border_color = Color(0.231, 0.510, 0.965, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	bg_panel.add_theme_stylebox_override("panel", sb)
	_sub_viewport.add_child(bg_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	bg_panel.add_child(vbox)

	_status_label = Label.new()
	_status_label.text = "VR XAI WRIST AUDIT · [PAUSADO]"
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.22, 0.74, 0.97))
	vbox.add_child(_status_label)

	_xai_rtl = RichTextLabel.new()
	_xai_rtl.bbcode_enabled = true
	_xai_rtl.scroll_following = true
	_xai_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_xai_rtl.add_theme_font_size_override("normal_font_size", 13)
	vbox.add_child(_xai_rtl)

	_quad_mesh_instance = MeshInstance3D.new()
	_quad_mesh_instance.name = "WristQuad3D"
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.26, 0.17)
	_quad_mesh_instance.mesh = quad

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _sub_viewport.get_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad_mesh_instance.material_override = mat
	add_child(_quad_mesh_instance)

func _on_sim_state_changed(new_state: GameConstants.SimState, _status_message: String) -> void:
	if _status_label != null:
		_status_label.text = "VR XAI WRIST · [%s]" % [GameConstants.get_sim_state_display_name(new_state)]

func _on_xai_rule_triggered(turn_number: int, rule_code: String, message: String) -> void:
	_push_vr_line("[T%02d] [%s] %s" % [turn_number, rule_code, message])

func _on_xai_cbr_triggered(turn_number: int, similarity: float, chosen_cell: Vector2i, reason: String) -> void:
	_push_vr_line("[T%02d] [RBC %.2f -> %s] %s" % [turn_number, similarity, str(chosen_cell), reason])

func _push_vr_line(line: String) -> void:
	_vr_lines.append(line)
	if _vr_lines.size() > 40:
		_vr_lines.pop_front()
	if _xai_rtl != null:
		_xai_rtl.text = "\n".join(_vr_lines)
