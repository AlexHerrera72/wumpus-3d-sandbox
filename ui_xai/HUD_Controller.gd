class_name HUD_Controller
extends CanvasLayer
## Interfaz XAI 2D: HUD_Controller
## Construye proceduralmente la interfaz 2D a 1280x800 (16:10) siguiendo el sistema
## de diseno editorial sobrio (design.md): grilla de 4px/8px, bordes sutiles de 1px,
## barra de herramientas Modo Dios, selector de cadencia de Ajedrez (0.5x, 1.0x, 2.0x),
## ventana modal interactiva para reconfigurar teclas de giro del tablero y consola
## de auditoria XAI en tiempo real.

const BG_SURFACE: Color = Color(0.071, 0.071, 0.082, 0.92)
const BG_ELEVATED: Color = Color(0.110, 0.110, 0.130, 0.96)
const BG_MODAL_OVERLAY: Color = Color(0.035, 0.035, 0.045, 0.78)
const BG_ACTIVE_ACCENT: Color = Color(0.145, 0.388, 0.922, 1.0)
const BORDER_SUBTLE: Color = Color(1.0, 1.0, 1.0, 0.14)
const BORDER_FOCUS: Color = Color(0.376, 0.647, 0.980, 0.90)
const TEXT_PRIMARY: Color = Color(0.98, 0.98, 0.98, 1.0)
const TEXT_SECONDARY: Color = Color(0.631, 0.631, 0.667, 1.0)

const SPEED_OPTIONS: Array[float] = [0.5, 1.0, 2.0]
const KEYBIND_ACTION_DEFS: Array[Dictionary] = [
	{"action": "board_rotate_left", "label": "Girar Tablero a la Izquierda (Yaw -)"},
	{"action": "board_rotate_right", "label": "Girar Tablero a la Derecha (Yaw +)"},
	{"action": "board_tilt_up", "label": "Inclinar Tablero Arriba (Pitch +)"},
	{"action": "board_tilt_down", "label": "Inclinar Tablero Abajo (Pitch -)"},
	{"action": "board_reset_rotation", "label": "Restablecer Giro a 0°"}
]

var _status_badge_label: Label
var _status_detail_label: Label
var _cursor_coord_label: Label
var _rig_mode_label: Label
var _xai_log_label: RichTextLabel

var _tool_buttons: Dictionary = {} # int (GodTool) -> Button
var _size_buttons: Dictionary = {} # Vector2i -> Button
var _keybind_buttons: Dictionary = {} # String (action_name) -> Button
var _btn_play_pause: Button
var _btn_speed_cycle: Button
var _btn_open_keybinds: Button

var _keybind_modal_backdrop: Control
var _waiting_rebind_action: String = ""
var _speed_index: int = 1 # 1.0x Ajedrez por defecto

var _active_tool: GameConstants.GodTool = GameConstants.GodTool.TOGGLE_PIT
var _current_sim_state: GameConstants.SimState = GameConstants.SimState.PAUSED
var _log_entries: Array[String] = []

func _ready() -> void:
	layer = 10
	_build_hud_layout()
	_build_keybind_modal()
	_connect_signals()
	_highlight_active_tool(_active_tool)
	_refresh_keybind_button_labels()

func _connect_signals() -> void:
	EventBus.god_tool_changed.connect(_on_god_tool_changed)
	EventBus.cursor_cell_hovered.connect(_on_cursor_cell_hovered)
	EventBus.sim_state_changed.connect(_on_sim_state_changed)
	EventBus.xai_rule_triggered.connect(_on_xai_rule_triggered)
	EventBus.xai_cbr_triggered.connect(_on_xai_cbr_triggered)
	EventBus.control_rig_switched.connect(_on_control_rig_switched)
	EventBus.world_truth_changed.connect(_on_world_truth_changed)
	EventBus.keybinds_updated.connect(_refresh_keybind_button_labels)

func _create_panel_style(bg: Color, border: Color, radius: int = 8, pad: int = 12) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = float(pad)
	sb.content_margin_right = float(pad)
	sb.content_margin_top = float(pad)
	sb.content_margin_bottom = float(pad)
	return sb

func _create_button_style(bg: Color, border: Color, radius: int = 6) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb

func _style_button(btn: Button, is_selected: bool = false) -> void:
	btn.custom_minimum_size = Vector2(0.0, 36.0)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	if is_selected:
		btn.add_theme_stylebox_override("normal", _create_button_style(BG_ACTIVE_ACCENT, BORDER_FOCUS))
		btn.add_theme_stylebox_override("hover", _create_button_style(BG_ACTIVE_ACCENT.lightened(0.08), BORDER_FOCUS))
		btn.add_theme_stylebox_override("pressed", _create_button_style(BG_ACTIVE_ACCENT.darkened(0.1), BORDER_FOCUS))
	else:
		btn.add_theme_stylebox_override("normal", _create_button_style(BG_ELEVATED, BORDER_SUBTLE))
		btn.add_theme_stylebox_override("hover", _create_button_style(BG_ELEVATED.lightened(0.08), BORDER_FOCUS))
		btn.add_theme_stylebox_override("pressed", _create_button_style(BG_ACTIVE_ACCENT, BORDER_FOCUS))

func _build_hud_layout() -> void:
	var root_margin: MarginContainer = MarginContainer.new()
	root_margin.name = "HUDRootMargin"
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_margin.add_theme_constant_override("margin_left", 16)
	root_margin.add_theme_constant_override("margin_right", 16)
	root_margin.add_theme_constant_override("margin_top", 16)
	root_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(root_margin)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_theme_constant_override("separation", 12)
	root_margin.add_child(main_vbox)

	# === BARRA SUPERIOR: ESTADO, VELOCIDAD AJEDREZ, RELOJ Y DIMENSION ===
	var top_bar: PanelContainer = PanelContainer.new()
	top_bar.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, BORDER_SUBTLE, 8, 12))
	main_vbox.add_child(top_bar)

	var top_hbox: HBoxContainer = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 8)
	top_bar.add_child(top_hbox)

	var title_vbox: VBoxContainer = VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 4)
	top_hbox.add_child(title_vbox)

	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	title_vbox.add_child(header_row)

	var app_title: Label = Label.new()
	app_title.text = "WUMPUS 3D SANDBOX · XAI"
	app_title.add_theme_font_size_override("font_size", 14)
	app_title.add_theme_color_override("font_color", TEXT_PRIMARY)
	header_row.add_child(app_title)

	_status_badge_label = Label.new()
	_status_badge_label.text = "[PAUSADO]"
	_status_badge_label.add_theme_font_size_override("font_size", 12)
	_status_badge_label.add_theme_color_override("font_color", Color(0.98, 0.80, 0.08))
	header_row.add_child(_status_badge_label)

	_status_detail_label = Label.new()
	_status_detail_label.text = "Inicializando simulacion..."
	_status_detail_label.add_theme_font_size_override("font_size", 11)
	_status_detail_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	title_vbox.add_child(_status_detail_label)

	var spacer_left: Control = Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_hbox.add_child(spacer_left)

	var sim_controls_hbox: HBoxContainer = HBoxContainer.new()
	sim_controls_hbox.add_theme_constant_override("separation", 8)
	top_hbox.add_child(sim_controls_hbox)

	_btn_play_pause = Button.new()
	_btn_play_pause.text = "▶ Iniciar (Espacio)"
	_style_button(_btn_play_pause, true)
	_btn_play_pause.pressed.connect(func() -> void: EventBus.sim_control_requested.emit("TOGGLE_PAUSE"))
	sim_controls_hbox.add_child(_btn_play_pause)

	var btn_step: Button = Button.new()
	btn_step.text = "⏭ 1 Paso (N)"
	_style_button(btn_step, false)
	btn_step.pressed.connect(func() -> void: EventBus.sim_control_requested.emit("STEP"))
	sim_controls_hbox.add_child(btn_step)

	var btn_reset: Button = Button.new()
	btn_reset.text = "↺ Reiniciar (R)"
	_style_button(btn_reset, false)
	btn_reset.pressed.connect(func() -> void: EventBus.sim_control_requested.emit("RESET"))
	sim_controls_hbox.add_child(btn_reset)

	# Selector de Cadencia de Ajedrez (Seccion 3.1)
	_btn_speed_cycle = Button.new()
	_btn_speed_cycle.text = "♟ Velocidad: 1.0x Ajedrez"
	_style_button(_btn_speed_cycle, false)
	_btn_speed_cycle.pressed.connect(_on_speed_cycle_pressed)
	sim_controls_hbox.add_child(_btn_speed_cycle)

	for dim: int in [4, 6, 8]:
		var vec_size: Vector2i = Vector2i(dim, dim)
		var b_size: Button = Button.new()
		b_size.text = "%dx%d" % [dim, dim]
		_style_button(b_size, dim == 6)
		b_size.pressed.connect(func() -> void: EventBus.board_resize_requested.emit(vec_size))
		sim_controls_hbox.add_child(b_size)
		_size_buttons[vec_size] = b_size

	# === ZONA CENTRAL: ESPACIO TRANSPARENTE + PANEL LATERAL XAI ===
	var middle_hbox: HBoxContainer = HBoxContainer.new()
	middle_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(middle_hbox)

	var viewport_spacer: Control = Control.new()
	viewport_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle_hbox.add_child(viewport_spacer)

	var xai_panel: PanelContainer = PanelContainer.new()
	xai_panel.custom_minimum_size = Vector2(392.0, 0.0)
	xai_panel.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, BORDER_SUBTLE, 8, 12))
	middle_hbox.add_child(xai_panel)

	var xai_vbox: VBoxContainer = VBoxContainer.new()
	xai_vbox.add_theme_constant_override("separation", 8)
	xai_panel.add_child(xai_vbox)

	var xai_header_hbox: HBoxContainer = HBoxContainer.new()
	xai_vbox.add_child(xai_header_hbox)

	var xai_title: Label = Label.new()
	xai_title.text = "AUDITORIA EXPLICABLE (RBR R1-R8 + 4R CBR)"
	xai_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xai_title.add_theme_font_size_override("font_size", 13)
	xai_title.add_theme_color_override("font_color", TEXT_PRIMARY)
	xai_header_hbox.add_child(xai_title)

	var btn_clear_log: Button = Button.new()
	btn_clear_log.text = "Limpiar"
	_style_button(btn_clear_log, false)
	btn_clear_log.custom_minimum_size = Vector2(68.0, 28.0)
	btn_clear_log.pressed.connect(_clear_xai_log)
	xai_header_hbox.add_child(btn_clear_log)

	var legend_label: Label = Label.new()
	legend_label.text = "Colores XAI: Verde=Segura | Cian=Visitada | Ambar=Sospechosa | Rojo=Peligro/Muro\nGiro Tablero: Flechas Teclado (Shift+Flecha = 90°)"
	legend_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend_label.add_theme_font_size_override("font_size", 11)
	legend_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	xai_vbox.add_child(legend_label)

	_xai_log_label = RichTextLabel.new()
	_xai_log_label.bbcode_enabled = true
	_xai_log_label.scroll_following = true
	_xai_log_label.selection_enabled = true
	_xai_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_xai_log_label.add_theme_font_size_override("normal_font_size", 12)
	_xai_log_label.add_theme_stylebox_override("normal", _create_panel_style(BG_ELEVATED, BORDER_SUBTLE, 6, 8))
	xai_vbox.add_child(_xai_log_label)

	# === BARRA INFERIOR: HERRAMIENTAS DEL MODO DIOS, GIRO Y RIG SWITCHER ===
	var bottom_bar: PanelContainer = PanelContainer.new()
	bottom_bar.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, BORDER_SUBTLE, 8, 12))
	main_vbox.add_child(bottom_bar)

	var bottom_hbox: HBoxContainer = HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 8)
	bottom_bar.add_child(bottom_hbox)

	var god_label: Label = Label.new()
	god_label.text = "MODO DIOS:"
	god_label.add_theme_font_size_override("font_size", 12)
	god_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	bottom_hbox.add_child(god_label)

	var tool_defs: Array[Dictionary] = [
		{"tool": GameConstants.GodTool.TOGGLE_PIT, "label": "1·Pozo"},
		{"tool": GameConstants.GodTool.TOGGLE_WUMPUS, "label": "2·Wumpus"},
		{"tool": GameConstants.GodTool.TOGGLE_WALL, "label": "3·Muro"},
		{"tool": GameConstants.GodTool.MOVE_GOLD, "label": "4·Oro"},
		{"tool": GameConstants.GodTool.CLEAR_CELL, "label": "5·Limpiar"}
	]

	for td: Dictionary in tool_defs:
		var t_enum: GameConstants.GodTool = td["tool"] as GameConstants.GodTool
		var btn: Button = Button.new()
		btn.text = String(td["label"])
		_style_button(btn, t_enum == _active_tool)
		btn.pressed.connect(func() -> void: EventBus.god_tool_changed.emit(t_enum))
		bottom_hbox.add_child(btn)
		_tool_buttons[int(t_enum)] = btn

	var bottom_spacer: Control = Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_hbox.add_child(bottom_spacer)

	_cursor_coord_label = Label.new()
	_cursor_coord_label.text = "Cursor: (0, 0)"
	_cursor_coord_label.add_theme_font_size_override("font_size", 12)
	_cursor_coord_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	bottom_hbox.add_child(_cursor_coord_label)

	var btn_reset_rot: Button = Button.new()
	btn_reset_rot.text = "0° Giro"
	_style_button(btn_reset_rot, false)
	btn_reset_rot.pressed.connect(func() -> void: EventBus.board_rotation_reset_requested.emit())
	bottom_hbox.add_child(btn_reset_rot)

	# Boton para abrir el modal de configuracion de teclas de giro (Seccion 3.2)
	_btn_open_keybinds = Button.new()
	_btn_open_keybinds.text = "⌨ Teclas Giro Tablero"
	_style_button(_btn_open_keybinds, false)
	_btn_open_keybinds.pressed.connect(_open_keybind_modal)
	bottom_hbox.add_child(_btn_open_keybinds)

	var btn_pc: Button = Button.new()
	btn_pc.text = "PC (F1)"
	_style_button(btn_pc, false)
	btn_pc.pressed.connect(func() -> void: PlatformManager.switch_rig_mode(GameConstants.ControlRigMode.PC_FREECAM))
	bottom_hbox.add_child(btn_pc)

	var btn_deck: Button = Button.new()
	btn_deck.text = "Deck (F2)"
	_style_button(btn_deck, false)
	btn_deck.pressed.connect(func() -> void: PlatformManager.switch_rig_mode(GameConstants.ControlRigMode.STEAM_DECK_GYRO))
	bottom_hbox.add_child(btn_deck)

	_rig_mode_label = Label.new()
	_rig_mode_label.text = "PC FreeCam"
	_rig_mode_label.add_theme_font_size_override("font_size", 12)
	_rig_mode_label.add_theme_color_override("font_color", Color(0.22, 0.74, 0.97))
	bottom_hbox.add_child(_rig_mode_label)

func _build_keybind_modal() -> void:
	_keybind_modal_backdrop = ColorRect.new()
	_keybind_modal_backdrop.name = "KeybindModalBackdrop"
	_keybind_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	(_keybind_modal_backdrop as ColorRect).color = BG_MODAL_OVERLAY
	_keybind_modal_backdrop.visible = false
	add_child(_keybind_modal_backdrop)

	var center_cont: CenterContainer = CenterContainer.new()
	center_cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	_keybind_modal_backdrop.add_child(center_cont)

	var modal_card: PanelContainer = PanelContainer.new()
	modal_card.custom_minimum_size = Vector2(520.0, 0.0)
	modal_card.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, BORDER_FOCUS, 12, 24))
	center_cont.add_child(modal_card)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	modal_card.add_child(vbox)

	var title_lbl: Label = Label.new()
	title_lbl.text = "CONFIGURAR TECLAS DE GIRO DEL TABLERO"
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", TEXT_PRIMARY)
	vbox.add_child(title_lbl)

	var sub_lbl: Label = Label.new()
	sub_lbl.text = "Haz clic en una accion y presiona cualquier tecla para reasignarla.\nTambien puedes usar Shift + Izquierda/Derecha para girar exactamente 90°."
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", TEXT_SECONDARY)
	vbox.add_child(sub_lbl)

	for def_entry: Dictionary in KEYBIND_ACTION_DEFS:
		var act_name: String = String(def_entry["action"])
		var act_label: String = String(def_entry["label"])

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		vbox.add_child(row)

		var lbl: Label = Label.new()
		lbl.text = act_label
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", TEXT_PRIMARY)
		row.add_child(lbl)

		var btn_rebind: Button = Button.new()
		btn_rebind.custom_minimum_size = Vector2(160.0, 36.0)
		_style_button(btn_rebind, false)
		btn_rebind.pressed.connect(func() -> void: _start_listening_for_key(act_name))
		row.add_child(btn_rebind)
		_keybind_buttons[act_name] = btn_rebind

	var footer_hbox: HBoxContainer = HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(footer_hbox)

	var btn_defaults: Button = Button.new()
	btn_defaults.text = "Restaurar Flechas por Defecto"
	_style_button(btn_defaults, false)
	btn_defaults.pressed.connect(func() -> void:
		_waiting_rebind_action = ""
		PlatformManager.reset_default_keybinds()
	)
	footer_hbox.add_child(btn_defaults)

	var f_spacer: Control = Control.new()
	f_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(f_spacer)

	var btn_close: Button = Button.new()
	btn_close.text = "Cerrar"
	_style_button(btn_close, true)
	btn_close.pressed.connect(_close_keybind_modal)
	footer_hbox.add_child(btn_close)

func _open_keybind_modal() -> void:
	_waiting_rebind_action = ""
	_refresh_keybind_button_labels()
	if _keybind_modal_backdrop != null:
		_keybind_modal_backdrop.visible = true

func _close_keybind_modal() -> void:
	_waiting_rebind_action = ""
	_refresh_keybind_button_labels()
	if _keybind_modal_backdrop != null:
		_keybind_modal_backdrop.visible = false

func _start_listening_for_key(action_name: String) -> void:
	_waiting_rebind_action = action_name
	_refresh_keybind_button_labels()
	if _keybind_buttons.has(action_name):
		var btn: Button = _keybind_buttons[action_name] as Button
		btn.text = "Presiona una tecla..."
		_style_button(btn, true)

func _refresh_keybind_button_labels() -> void:
	for act_name: String in _keybind_buttons.keys():
		var btn: Button = _keybind_buttons[act_name] as Button
		var key_str: String = PlatformManager.get_action_key_label(act_name)
		btn.text = "[ %s ]" % [key_str]
		_style_button(btn, act_name == _waiting_rebind_action)

func _unhandled_key_input(event: InputEvent) -> void:
	if _waiting_rebind_action.is_empty():
		return
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_ESCAPE:
				_waiting_rebind_action = ""
				_refresh_keybind_button_labels()
			else:
				var target_action: String = _waiting_rebind_action
				_waiting_rebind_action = ""
				PlatformManager.rebind_action_key(target_action, ke.keycode)
			get_viewport().set_input_as_handled()

func _on_speed_cycle_pressed() -> void:
	_speed_index = (_speed_index + 1) % SPEED_OPTIONS.size()
	var mult: float = SPEED_OPTIONS[_speed_index]
	var label_desc: String = "Ajedrez"
	if mult < 0.8:
		label_desc = "Lento"
	elif mult > 1.5:
		label_desc = "Rapido"
	if _btn_speed_cycle != null:
		_btn_speed_cycle.text = "♟ Velocidad: %.1fx %s" % [mult, label_desc]
	EventBus.sim_speed_changed.emit(mult)

func _highlight_active_tool(tool_id: GameConstants.GodTool) -> void:
	_active_tool = tool_id
	for key: int in _tool_buttons.keys():
		var btn: Button = _tool_buttons[key] as Button
		_style_button(btn, key == int(tool_id))

func _on_god_tool_changed(new_tool: GameConstants.GodTool) -> void:
	_highlight_active_tool(new_tool)

func _on_cursor_cell_hovered(cell: Vector2i, is_valid: bool) -> void:
	if _cursor_coord_label == null:
		return
	if is_valid:
		_cursor_coord_label.text = "Cursor: (%d, %d)" % [cell.x, cell.y]
	else:
		_cursor_coord_label.text = "Cursor: Fuera"

func _on_sim_state_changed(new_state: GameConstants.SimState, status_message: String) -> void:
	_current_sim_state = new_state
	if _status_badge_label != null:
		_status_badge_label.text = "[%s]" % [GameConstants.get_sim_state_display_name(new_state)]
		match new_state:
			GameConstants.SimState.RUNNING:
				_status_badge_label.add_theme_color_override("font_color", Color(0.29, 0.87, 0.50))
			GameConstants.SimState.PAUSED, GameConstants.SimState.STEPPING:
				_status_badge_label.add_theme_color_override("font_color", Color(0.98, 0.80, 0.08))
			GameConstants.SimState.WAITING_FOR_GOD_MODE:
				_status_badge_label.add_theme_color_override("font_color", Color(0.98, 0.57, 0.24))
			GameConstants.SimState.VICTORY:
				_status_badge_label.add_theme_color_override("font_color", Color(0.22, 0.74, 0.97))
			GameConstants.SimState.GAME_OVER:
				_status_badge_label.add_theme_color_override("font_color", Color(0.97, 0.44, 0.44))

	if _status_detail_label != null:
		_status_detail_label.text = status_message

	if _btn_play_pause != null:
		if new_state == GameConstants.SimState.RUNNING:
			_btn_play_pause.text = "⏸ Pausar (Espacio)"
		else:
			_btn_play_pause.text = "▶ Iniciar (Espacio)"

func _on_control_rig_switched(new_mode: GameConstants.ControlRigMode) -> void:
	if _rig_mode_label == null:
		return
	match new_mode:
		GameConstants.ControlRigMode.PC_FREECAM:
			_rig_mode_label.text = "PC FreeCam"
		GameConstants.ControlRigMode.STEAM_DECK_GYRO:
			_rig_mode_label.text = "Deck Gyro"
		GameConstants.ControlRigMode.VR_OPENXR:
			_rig_mode_label.text = "OpenXR VR"

func _on_world_truth_changed(truth_snapshot: Dictionary) -> void:
	var g_size: Vector2i = truth_snapshot.get("grid_size", GameConstants.DEFAULT_GRID_SIZE) as Vector2i
	for k: Vector2i in _size_buttons.keys():
		var b: Button = _size_buttons[k] as Button
		_style_button(b, k == g_size)

func _on_xai_rule_triggered(turn_number: int, rule_code: String, message: String) -> void:
	var color_hex: String = "#38BDF8"
	if rule_code.begins_with("R1") or rule_code.begins_with("R2") or rule_code.begins_with("R3"):
		color_hex = "#4ADE80"
	elif rule_code.begins_with("R4"):
		color_hex = "#FACC15"
	elif rule_code.begins_with("R5") or rule_code.begins_with("R6") or rule_code == "FATAL":
		color_hex = "#F87171"
	elif rule_code.begins_with("R7") or rule_code == "VICTORY":
		color_hex = "#FBBF24"
	elif rule_code.begins_with("R8") or rule_code.begins_with("GOD") or rule_code.begins_with("WAIT"):
		color_hex = "#FB923C"

	var line: String = "[color=#71717A][T%02d][/color] [b][color=%s][%s][/color][/b] %s" % [
		turn_number, color_hex, rule_code, message
	]
	_append_log_line(line)

func _on_xai_cbr_triggered(turn_number: int, similarity: float, chosen_cell: Vector2i, reason: String) -> void:
	var line: String = "[color=#71717A][T%02d][/color] [b][color=#60A5FA][RBC-4R Sim=%.2f -> %s][/color][/b] %s" % [
		turn_number, similarity, str(chosen_cell), reason
	]
	_append_log_line(line)

func _append_log_line(bbcode_line: String) -> void:
	_log_entries.append(bbcode_line)
	if _log_entries.size() > 160:
		_log_entries.pop_front()
	if _xai_log_label != null:
		_xai_log_label.text = "\n".join(_log_entries)

func _clear_xai_log() -> void:
	_log_entries.clear()
	if _xai_log_label != null:
		_xai_log_label.text = ""
