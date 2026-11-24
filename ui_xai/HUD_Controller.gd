class_name HUD_Controller
extends CanvasLayer
## Interfaz UI/UX Minimalista: HUD_Controller
## Diseno depurado con textos minimos, iconos claros y mini-pestanas translucidas
## (tooltips) solo al reposar el cursor sobre botones del HUD.
## Incluye:
##   - Pantalla de Inicio (Iniciar, Opciones, Cerrar)
##   - Opciones: PC (Teclado) vs Mando General (4 Botones + 2 Joysticks) + Probador
##   - HUD en juego: Menu ☰ (izq), Play ▶/⏸ + Stop ■ (der), Pestana Terminal ◀/▶
##     translucida sin titulos innecesarios, Flechas de Piso ▼/▲ (arriba centro)
##   - Confirmacion modal al reducir tamano del mapa (sin borrar al expandir).

const BG_CANVAS_SCRIM: Color = Color(0.035, 0.035, 0.045, 0.78)
const BG_SURFACE: Color = Color(0.071, 0.071, 0.082, 0.92)
const BG_XAI_GLASS: Color = Color(0.055, 0.060, 0.075, 0.72)
const BG_TOOLTIP_GLASS: Color = Color(0.055, 0.060, 0.078, 0.84)
const BG_ELEVATED: Color = Color(0.110, 0.110, 0.130, 0.94)
const BG_ACTIVE_ACCENT: Color = Color(0.145, 0.388, 0.922, 1.0)
const BG_SUCCESS_PULSE: Color = Color(0.133, 0.545, 0.290, 1.0)
const BG_DANGER_SUBTLE: Color = Color(0.28, 0.09, 0.10, 0.95)
const BORDER_SUBTLE: Color = Color(1.0, 1.0, 1.0, 0.15)
const BORDER_FOCUS: Color = Color(0.376, 0.647, 0.980, 0.90)
const TEXT_PRIMARY: Color = Color(0.98, 0.98, 0.98, 1.0)
const TEXT_SECONDARY: Color = Color(0.631, 0.631, 0.667, 1.0)

const DRAWER_WIDTH: float = 286.0
const XAI_DRAWER_WIDTH: float = 360.0
const XAI_TAB_WIDTH: float = 30.0
const SPEED_OPTIONS: Array[float] = [0.5, 1.0, 2.0]

const PC_REBIND_DEFS: Array[Dictionary] = [
	{"action": "action_primary", "label": "Play / Pausa"},
	{"action": "action_back", "label": "Stop / Reiniciar"},
	{"action": "action_menu", "label": "Menu"},
	{"action": "action_aux", "label": "Cambiar Herramienta"},
	{"action": "board_rotate_left", "label": "Girar Izquierda"},
	{"action": "board_rotate_right", "label": "Girar Derecha"},
	{"action": "board_tilt_up", "label": "Inclinar Arriba"},
	{"action": "board_tilt_down", "label": "Inclinar Abajo"},
	{"action": "board_reset_rotation", "label": "Giro 0°"},
	{"action": "floor_up", "label": "Subir Piso"},
	{"action": "floor_down", "label": "Bajar Piso"}
]

const GAMEPAD_REBIND_DEFS: Array[Dictionary] = [
	{"action": "action_primary", "label": "Der 1 · Play"},
	{"action": "action_back", "label": "Der 2 · Stop"},
	{"action": "action_menu", "label": "Izq 1 · Menu"},
	{"action": "action_aux", "label": "Izq 2 · Aux"},
	{"action": "floor_up", "label": "Subir Piso"},
	{"action": "floor_down", "label": "Bajar Piso"},
	{"action": "board_reset_rotation", "label": "Giro 0°"}
]

var _hud_theme: Theme
var _current_screen: String = "START_MENU"
var _return_screen: String = "START_MENU"
var _options_tab: String = "PC"

var _is_drawer_open: bool = false
var _drawer_tween: Tween
var _is_xai_open: bool = false
var _xai_tween: Tween

var _active_tool: GameConstants.GodTool = GameConstants.GodTool.TOGGLE_PIT
var _current_sim_state: GameConstants.SimState = GameConstants.SimState.PAUSED
var _current_grid_size: Vector2i = GameConstants.DEFAULT_GRID_SIZE
var _pending_shrink_size: Vector2i = Vector2i.ZERO
var _speed_index: int = 1
var _active_floor: int = 0
var _floor_count: int = 1

var _waiting_rebind_action: String = ""
var _waiting_rebind_mode: String = ""

# Contenedores principales
var _start_screen_overlay: Control
var _options_overlay: Control
var _gameplay_root: Control
var _drawer_panel: PanelContainer
var _xai_slide_wrapper: Control
var _btn_xai_tab: Button
var _xai_log_label: RichTextLabel
var _log_entries: Array[String] = []
var _shrink_confirm_overlay: Control
var _shrink_confirm_label: Label

# HUD minimalista en juego
var _btn_hud_menu: Button
var _lbl_hud_menu_key: Label
var _btn_hud_play: Button
var _lbl_hud_play_icon: Label
var _lbl_hud_play_key: Label
var _btn_hud_stop: Button
var _lbl_hud_stop_key: Label

# Barra de flechas de piso
var _floor_bar_panel: PanelContainer
var _btn_floor_down: Button
var _btn_floor_up: Button
var _lbl_floor_indicator: Label

# Notificacion / Validacion flotante
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween

# Controles dentro del Drawer izquierdo
var _tool_buttons: Dictionary = {} # int (GodTool) -> Button
var _size_buttons: Dictionary = {} # Vector2i -> Button
var _lbl_floor_count_info: Label
var _btn_add_floor: Button
var _btn_remove_floor: Button
var _btn_speed_cycle: Button
var _lbl_inventory_status: Label
var _map_name_input: LineEdit
var _saved_maps_dropdown: OptionButton

# Controles dentro de Opciones
var _btn_tab_pc: Button
var _btn_tab_gamepad: Button
var _pc_binds_container: Control
var _gamepad_binds_container: Control
var _pc_rebind_buttons: Dictionary = {}
var _gamepad_rebind_buttons: Dictionary = {}
var _test_pills: Dictionary = {}
var _vr_test_states: Dictionary = {}
var _lbl_left_stick_val: Label
var _lbl_right_stick_val: Label
var _lbl_joypad_detected: Label
var _bar_lx: ProgressBar
var _bar_ly: ProgressBar
var _bar_rx: ProgressBar
var _bar_ry: ProgressBar

func _ready() -> void:
	layer = 10
	_build_hud_theme()
	_build_gameplay_hud_and_drawers()
	_build_shrink_confirm_modal()
	_build_start_screen()
	_build_options_screen()
	_connect_signals()

	_highlight_active_tool(_active_tool)
	_refresh_all_keybind_labels()
	_set_options_tab("PC")
	_set_screen("START_MENU")

func _build_hud_theme() -> void:
	_hud_theme = Theme.new()
	var tip_panel: StyleBoxFlat = _create_panel_style(BG_TOOLTIP_GLASS, BORDER_SUBTLE, 6, 8)
	_hud_theme.set_stylebox("panel", "TooltipPanel", tip_panel)
	_hud_theme.set_color("font_color", "TooltipLabel", TEXT_PRIMARY)
	_hud_theme.set_font_size("font_size", "TooltipLabel", 11)

func _connect_signals() -> void:
	EventBus.god_tool_changed.connect(_on_god_tool_changed)
	EventBus.sim_state_changed.connect(_on_sim_state_changed)
	EventBus.xai_rule_triggered.connect(_on_xai_rule_triggered)
	EventBus.xai_cbr_triggered.connect(_on_xai_cbr_triggered)
	EventBus.world_truth_changed.connect(_on_world_truth_changed)
	EventBus.keybinds_updated.connect(_refresh_all_keybind_labels)
	EventBus.menu_drawer_toggled.connect(_toggle_drawer)
	EventBus.xai_panel_toggled.connect(_toggle_xai_drawer)
	EventBus.active_floor_changed.connect(_on_active_floor_changed)
	EventBus.saved_maps_list_updated.connect(_on_saved_maps_list_updated)
	EventBus.ui_notification_requested.connect(_show_toast)
	EventBus.agent_inventory_updated.connect(_on_agent_inventory_updated)
	EventBus.vr_input_test_pulse.connect(_on_vr_input_test_pulse)

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

func _create_button_style(bg: Color, border: Color, radius: int = 6, pad_h: float = 10.0, pad_v: float = 6.0) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb

func _style_button(btn: Button, is_selected: bool = false, is_danger: bool = false, height: float = 34.0) -> void:
	btn.custom_minimum_size = Vector2(btn.custom_minimum_size.x, height)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	if is_danger:
		btn.add_theme_stylebox_override("normal", _create_button_style(BG_DANGER_SUBTLE, Color(0.95, 0.35, 0.35, 0.50)))
		btn.add_theme_stylebox_override("hover", _create_button_style(BG_DANGER_SUBTLE.lightened(0.12), Color(0.98, 0.45, 0.45, 0.85)))
		btn.add_theme_stylebox_override("pressed", _create_button_style(BG_DANGER_SUBTLE.darkened(0.12), Color(0.98, 0.45, 0.45, 0.95)))
	elif is_selected:
		btn.add_theme_stylebox_override("normal", _create_button_style(BG_ACTIVE_ACCENT, BORDER_FOCUS))
		btn.add_theme_stylebox_override("hover", _create_button_style(BG_ACTIVE_ACCENT.lightened(0.08), BORDER_FOCUS))
		btn.add_theme_stylebox_override("pressed", _create_button_style(BG_ACTIVE_ACCENT.darkened(0.1), BORDER_FOCUS))
	else:
		btn.add_theme_stylebox_override("normal", _create_button_style(BG_ELEVATED, BORDER_SUBTLE))
		btn.add_theme_stylebox_override("hover", _create_button_style(BG_ELEVATED.lightened(0.08), BORDER_FOCUS))
		btn.add_theme_stylebox_override("pressed", _create_button_style(BG_ACTIVE_ACCENT, BORDER_FOCUS))

func _style_icon_action_button(btn: Button, accent: bool = false) -> void:
	btn.custom_minimum_size = Vector2(54.0, 54.0)
	var base_bg: Color = BG_ACTIVE_ACCENT if accent else BG_SURFACE
	var base_border: Color = BORDER_FOCUS if accent else BORDER_SUBTLE
	btn.add_theme_stylebox_override("normal", _create_button_style(base_bg, base_border, 10, 4.0, 4.0))
	btn.add_theme_stylebox_override("hover", _create_button_style(base_bg.lightened(0.1), BORDER_FOCUS, 10, 4.0, 4.0))
	btn.add_theme_stylebox_override("pressed", _create_button_style(BG_ACTIVE_ACCENT, BORDER_FOCUS, 10, 4.0, 4.0))

func _make_divider() -> ColorRect:
	var line: ColorRect = ColorRect.new()
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.color = BORDER_SUBTLE
	return line

# ==============================================================================
# 1. PANTALLA DE INICIO (MINIMALISTA: INICIAR / OPCIONES / CERRAR)
# ==============================================================================
func _build_start_screen() -> void:
	_start_screen_overlay = ColorRect.new()
	_start_screen_overlay.name = "StartScreenOverlay"
	_start_screen_overlay.theme = _hud_theme
	_start_screen_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	(_start_screen_overlay as ColorRect).color = BG_CANVAS_SCRIM
	add_child(_start_screen_overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_start_screen_overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(460.0, 0.0)
	card.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, BORDER_SUBTLE, 12, 28))
	center.add_child(card)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 4)
	vbox.add_child(title_box)

	var title_lbl: Label = Label.new()
	title_lbl.text = "La maravillosa aventura del Amongus asesino de Wumpus"
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", TEXT_PRIMARY)
	title_box.add_child(title_lbl)

	var pending_lbl: Label = Label.new()
	pending_lbl.text = "(cambio de nombre pendiente)"
	pending_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pending_lbl.add_theme_font_size_override("font_size", 11)
	pending_lbl.add_theme_color_override("font_color", TEXT_SECONDARY)
	title_box.add_child(pending_lbl)

	vbox.add_child(_make_divider())

	var btn_start: Button = Button.new()
	btn_start.text = "Iniciar"
	_style_button(btn_start, true, false, 46.0)
	btn_start.add_theme_font_size_override("font_size", 15)
	btn_start.pressed.connect(func() -> void: _set_screen("GAMEPLAY"))
	vbox.add_child(btn_start)

	var btn_options: Button = Button.new()
	btn_options.text = "Opciones"
	_style_button(btn_options, false, false, 42.0)
	btn_options.add_theme_font_size_override("font_size", 14)
	btn_options.pressed.connect(func() -> void:
		_return_screen = "START_MENU"
		_set_screen("OPTIONS")
	)
	vbox.add_child(btn_options)

	var btn_quit: Button = Button.new()
	btn_quit.text = "Cerrar"
	_style_button(btn_quit, false, true, 42.0)
	btn_quit.add_theme_font_size_override("font_size", 14)
	btn_quit.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(btn_quit)

# ==============================================================================
# 2. OPCIONES: PC (TECLADO) vs MANDO GENERAL (4 BOTONES + 2 JOYSTICKS)
# ==============================================================================
func _build_options_screen() -> void:
	_options_overlay = ColorRect.new()
	_options_overlay.name = "OptionsOverlay"
	_options_overlay.theme = _hud_theme
	_options_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	(_options_overlay as ColorRect).color = BG_CANVAS_SCRIM
	_options_overlay.visible = false
	add_child(_options_overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options_overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(920.0, 580.0)
	card.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, BORDER_SUBTLE, 12, 24))
	center.add_child(card)

	var outer_vbox: VBoxContainer = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 16)
	card.add_child(outer_vbox)

	var header_hbox: HBoxContainer = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 12)
	outer_vbox.add_child(header_hbox)

	var opt_title: Label = Label.new()
	opt_title.text = "Opciones"
	opt_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_title.add_theme_font_size_override("font_size", 18)
	opt_title.add_theme_color_override("font_color", TEXT_PRIMARY)
	header_hbox.add_child(opt_title)

	var btn_restore_def: Button = Button.new()
	btn_restore_def.text = "Restaurar"
	btn_restore_def.tooltip_text = "Restaurar controles por defecto de esta pestana"
	_style_button(btn_restore_def, false, false, 34.0)
	btn_restore_def.pressed.connect(func() -> void:
		_waiting_rebind_action = ""
		_waiting_rebind_mode = ""
		if _options_tab == "PC":
			PlatformManager.reset_pc_keybinds()
		else:
			PlatformManager.reset_gamepad_keybinds()
	)
	header_hbox.add_child(btn_restore_def)

	var btn_back: Button = Button.new()
	btn_back.text = "Volver"
	_style_button(btn_back, true, false, 34.0)
	btn_back.pressed.connect(func() -> void:
		_waiting_rebind_action = ""
		_waiting_rebind_mode = ""
		_set_screen(_return_screen)
	)
	header_hbox.add_child(btn_back)

	outer_vbox.add_child(_make_divider())

	var cols_hbox: HBoxContainer = HBoxContainer.new()
	cols_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols_hbox.add_theme_constant_override("separation", 24)
	outer_vbox.add_child(cols_hbox)

	# --- Izquierda: Pestanas PC / Mando ---
	var left_vbox: VBoxContainer = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_stretch_ratio = 1.2
	left_vbox.add_theme_constant_override("separation", 12)
	cols_hbox.add_child(left_vbox)

	var tabs_hbox: HBoxContainer = HBoxContainer.new()
	tabs_hbox.add_theme_constant_override("separation", 8)
	left_vbox.add_child(tabs_hbox)

	_btn_tab_pc = Button.new()
	_btn_tab_pc.text = "PC (Teclado)"
	_btn_tab_pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(_btn_tab_pc, true, false, 38.0)
	_btn_tab_pc.pressed.connect(func() -> void: _set_options_tab("PC"))
	tabs_hbox.add_child(_btn_tab_pc)

	_btn_tab_gamepad = Button.new()
	_btn_tab_gamepad.text = "Mando (4 Botones + 2 Sticks)"
	_btn_tab_gamepad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(_btn_tab_gamepad, false, false, 38.0)
	_btn_tab_gamepad.pressed.connect(func() -> void: _set_options_tab("GAMEPAD"))
	tabs_hbox.add_child(_btn_tab_gamepad)

	var pc_scroll: ScrollContainer = ScrollContainer.new()
	pc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(pc_scroll)
	_pc_binds_container = pc_scroll

	var pc_list: VBoxContainer = VBoxContainer.new()
	pc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc_list.add_theme_constant_override("separation", 8)
	pc_scroll.add_child(pc_list)

	for def_entry: Dictionary in PC_REBIND_DEFS:
		var act_name: String = String(def_entry["action"])
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		pc_list.add_child(row)

		var l_name: Label = Label.new()
		l_name.text = String(def_entry["label"])
		l_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l_name.add_theme_font_size_override("font_size", 13)
		l_name.add_theme_color_override("font_color", TEXT_PRIMARY)
		row.add_child(l_name)

		var btn_bind: Button = Button.new()
		btn_bind.custom_minimum_size = Vector2(150.0, 32.0)
		btn_bind.tooltip_text = "Haz clic y pulsa una tecla para reasignar"
		_style_button(btn_bind, false, false, 32.0)
		btn_bind.pressed.connect(func() -> void: _start_listening_rebind(act_name, "PC"))
		row.add_child(btn_bind)
		_pc_rebind_buttons[act_name] = btn_bind

	var gp_scroll: ScrollContainer = ScrollContainer.new()
	gp_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gp_scroll.visible = false
	left_vbox.add_child(gp_scroll)
	_gamepad_binds_container = gp_scroll

	var gp_list: VBoxContainer = VBoxContainer.new()
	gp_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gp_list.add_theme_constant_override("separation", 8)
	gp_scroll.add_child(gp_list)

	for def_entry: Dictionary in GAMEPAD_REBIND_DEFS:
		var act_name: String = String(def_entry["action"])
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		gp_list.add_child(row)

		var l_name: Label = Label.new()
		l_name.text = String(def_entry["label"])
		l_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l_name.add_theme_font_size_override("font_size", 13)
		l_name.add_theme_color_override("font_color", TEXT_PRIMARY)
		row.add_child(l_name)

		var btn_bind: Button = Button.new()
		btn_bind.custom_minimum_size = Vector2(150.0, 32.0)
		btn_bind.tooltip_text = "Haz clic y pulsa un boton del mando"
		_style_button(btn_bind, false, false, 32.0)
		btn_bind.pressed.connect(func() -> void: _start_listening_rebind(act_name, "GAMEPAD"))
		row.add_child(btn_bind)
		_gamepad_rebind_buttons[act_name] = btn_bind

	# --- Derecha: Probador en Vivo ---
	var right_panel: PanelContainer = PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.9
	right_panel.add_theme_stylebox_override("panel", _create_panel_style(BG_ELEVATED, BORDER_SUBTLE, 8, 16))
	cols_hbox.add_child(right_panel)

	var tester_vbox: VBoxContainer = VBoxContainer.new()
	tester_vbox.add_theme_constant_override("separation", 12)
	right_panel.add_child(tester_vbox)

	var tester_title: Label = Label.new()
	tester_title.text = "Prueba de Entrada"
	tester_title.add_theme_font_size_override("font_size", 14)
	tester_title.add_theme_color_override("font_color", TEXT_PRIMARY)
	tester_vbox.add_child(tester_title)

	_lbl_joypad_detected = Label.new()
	_lbl_joypad_detected.text = "Mandos: 0"
	_lbl_joypad_detected.add_theme_font_size_override("font_size", 12)
	_lbl_joypad_detected.add_theme_color_override("font_color", Color(0.22, 0.74, 0.97))
	tester_vbox.add_child(_lbl_joypad_detected)

	var grid_test: GridContainer = GridContainer.new()
	grid_test.columns = 2
	grid_test.add_theme_constant_override("h_separation", 8)
	grid_test.add_theme_constant_override("v_separation", 8)
	tester_vbox.add_child(grid_test)

	var pill_defs: Array[Dictionary] = [
		{"action": "action_menu", "title": "☰"},
		{"action": "action_primary", "title": "▶"},
		{"action": "action_aux", "title": "↻"},
		{"action": "action_back", "title": "■"}
	]
	for pd: Dictionary in pill_defs:
		var a_key: String = String(pd["action"])
		var pill: PanelContainer = PanelContainer.new()
		pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pill.custom_minimum_size = Vector2(0.0, 54.0)
		pill.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, BORDER_SUBTLE, 8, 8))
		grid_test.add_child(pill)

		var pl: Label = Label.new()
		pl.text = String(pd["title"])
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pl.add_theme_font_size_override("font_size", 20)
		pl.add_theme_color_override("font_color", TEXT_PRIMARY)
		pill.add_child(pl)

		_test_pills[a_key] = pill

	tester_vbox.add_child(_make_divider())

	_lbl_left_stick_val = Label.new()
	_lbl_left_stick_val.text = "Stick Izq: 0.00, 0.00"
	_lbl_left_stick_val.add_theme_font_size_override("font_size", 12)
	_lbl_left_stick_val.add_theme_color_override("font_color", TEXT_SECONDARY)
	tester_vbox.add_child(_lbl_left_stick_val)

	_bar_lx = _create_axis_bar()
	_bar_ly = _create_axis_bar()
	tester_vbox.add_child(_bar_lx)
	tester_vbox.add_child(_bar_ly)

	_lbl_right_stick_val = Label.new()
	_lbl_right_stick_val.text = "Stick Der: 0.00, 0.00"
	_lbl_right_stick_val.add_theme_font_size_override("font_size", 12)
	_lbl_right_stick_val.add_theme_color_override("font_color", TEXT_SECONDARY)
	tester_vbox.add_child(_lbl_right_stick_val)

	_bar_rx = _create_axis_bar()
	_bar_ry = _create_axis_bar()
	tester_vbox.add_child(_bar_rx)
	tester_vbox.add_child(_bar_ry)

func _create_axis_bar() -> ProgressBar:
	var pb: ProgressBar = ProgressBar.new()
	pb.min_value = -1.0
	pb.max_value = 1.0
	pb.value = 0.0
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0.0, 10.0)
	return pb

func _set_options_tab(tab_name: String) -> void:
	_options_tab = tab_name
	_waiting_rebind_action = ""
	_waiting_rebind_mode = ""
	if _pc_binds_container != null:
		_pc_binds_container.visible = (tab_name == "PC")
	if _gamepad_binds_container != null:
		_gamepad_binds_container.visible = (tab_name == "GAMEPAD")
	if _btn_tab_pc != null:
		_style_button(_btn_tab_pc, tab_name == "PC", false, 38.0)
	if _btn_tab_gamepad != null:
		_style_button(_btn_tab_gamepad, tab_name == "GAMEPAD", false, 38.0)
	_refresh_all_keybind_labels()

# ==============================================================================
# 3. HUD MINIMALISTA + DRAWER IZQUIERDO + PESTANA TERMINAL DERECHA SIN TEXTO
# ==============================================================================
func _build_gameplay_hud_and_drawers() -> void:
	_gameplay_root = Control.new()
	_gameplay_root.name = "GameplayHUDRoot"
	_gameplay_root.theme = _hud_theme
	_gameplay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gameplay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gameplay_root)

	# --- ARRIBA IZQUIERDA: SOLO ICONO ☰ + TECLA ---
	_btn_hud_menu = Button.new()
	_btn_hud_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_btn_hud_menu.position = Vector2(16.0, 16.0)
	_btn_hud_menu.tooltip_text = "Menu de construccion y mapas"
	_style_icon_action_button(_btn_hud_menu, false)
	_btn_hud_menu.pressed.connect(_toggle_drawer)
	_gameplay_root.add_child(_btn_hud_menu)

	var menu_btn_vb: VBoxContainer = VBoxContainer.new()
	menu_btn_vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_btn_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_btn_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_btn_vb.add_theme_constant_override("separation", 0)
	_btn_hud_menu.add_child(menu_btn_vb)

	var menu_icon: Label = Label.new()
	menu_icon.text = "☰"
	menu_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_icon.add_theme_font_size_override("font_size", 21)
	menu_icon.add_theme_color_override("font_color", TEXT_PRIMARY)
	menu_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_btn_vb.add_child(menu_icon)

	_lbl_hud_menu_key = Label.new()
	_lbl_hud_menu_key.text = "TAB"
	_lbl_hud_menu_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_hud_menu_key.add_theme_font_size_override("font_size", 10)
	_lbl_hud_menu_key.add_theme_color_override("font_color", TEXT_SECONDARY)
	_lbl_hud_menu_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_btn_vb.add_child(_lbl_hud_menu_key)

	# --- ARRIBA DERECHA: SOLO 2 ICONOS PEQUENOS (PLAY Y STOP) ---
	var right_actions_hbox: HBoxContainer = HBoxContainer.new()
	right_actions_hbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_actions_hbox.offset_left = -132.0
	right_actions_hbox.offset_top = 16.0
	right_actions_hbox.offset_right = -16.0
	right_actions_hbox.offset_bottom = 70.0
	right_actions_hbox.add_theme_constant_override("separation", 8)
	_gameplay_root.add_child(right_actions_hbox)

	_btn_hud_play = Button.new()
	_btn_hud_play.tooltip_text = "Iniciar / Pausar simulacion (la camara sigue al agente)"
	_style_icon_action_button(_btn_hud_play, true)
	_btn_hud_play.pressed.connect(func() -> void: EventBus.sim_control_requested.emit("TOGGLE_PAUSE"))
	right_actions_hbox.add_child(_btn_hud_play)

	var play_vb: VBoxContainer = VBoxContainer.new()
	play_vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	play_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_vb.add_theme_constant_override("separation", 0)
	_btn_hud_play.add_child(play_vb)

	_lbl_hud_play_icon = Label.new()
	_lbl_hud_play_icon.text = "▶"
	_lbl_hud_play_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_hud_play_icon.add_theme_font_size_override("font_size", 19)
	_lbl_hud_play_icon.add_theme_color_override("font_color", TEXT_PRIMARY)
	_lbl_hud_play_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_vb.add_child(_lbl_hud_play_icon)

	_lbl_hud_play_key = Label.new()
	_lbl_hud_play_key.text = "SPC"
	_lbl_hud_play_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_hud_play_key.add_theme_font_size_override("font_size", 10)
	_lbl_hud_play_key.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	_lbl_hud_play_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_vb.add_child(_lbl_hud_play_key)

	_btn_hud_stop = Button.new()
	_btn_hud_stop.tooltip_text = "Detener y devolver al agente a (0,0) conservando tu mapa"
	_style_icon_action_button(_btn_hud_stop, false)
	_btn_hud_stop.pressed.connect(func() -> void: EventBus.sim_control_requested.emit("RESET"))
	right_actions_hbox.add_child(_btn_hud_stop)

	var stop_vb: VBoxContainer = VBoxContainer.new()
	stop_vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	stop_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	stop_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stop_vb.add_theme_constant_override("separation", 0)
	_btn_hud_stop.add_child(stop_vb)

	var stop_icon: Label = Label.new()
	stop_icon.text = "■"
	stop_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stop_icon.add_theme_font_size_override("font_size", 18)
	stop_icon.add_theme_color_override("font_color", TEXT_PRIMARY)
	stop_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stop_vb.add_child(stop_icon)

	_lbl_hud_stop_key = Label.new()
	_lbl_hud_stop_key.text = "BKSP"
	_lbl_hud_stop_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_hud_stop_key.add_theme_font_size_override("font_size", 10)
	_lbl_hud_stop_key.add_theme_color_override("font_color", TEXT_SECONDARY)
	_lbl_hud_stop_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stop_vb.add_child(_lbl_hud_stop_key)

	# --- ARRIBA CENTRO: FLECHAS DE PISO ▼ P1/5 ▲ (SOLO CON 2+ PISOS) ---
	_floor_bar_panel = PanelContainer.new()
	_floor_bar_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_floor_bar_panel.offset_left = -84.0
	_floor_bar_panel.offset_right = 84.0
	_floor_bar_panel.offset_top = 16.0
	_floor_bar_panel.offset_bottom = 60.0
	_floor_bar_panel.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, BORDER_SUBTLE, 10, 4))
	_floor_bar_panel.visible = false
	_gameplay_root.add_child(_floor_bar_panel)

	var fl_hb: HBoxContainer = HBoxContainer.new()
	fl_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	fl_hb.add_theme_constant_override("separation", 6)
	_floor_bar_panel.add_child(fl_hb)

	_btn_floor_down = Button.new()
	_btn_floor_down.text = "▼"
	_btn_floor_down.tooltip_text = "Bajar un piso"
	_btn_floor_down.custom_minimum_size = Vector2(36.0, 32.0)
	_style_button(_btn_floor_down, false, false, 32.0)
	_btn_floor_down.pressed.connect(func() -> void: EventBus.active_floor_step_requested.emit(-1))
	fl_hb.add_child(_btn_floor_down)

	_lbl_floor_indicator = Label.new()
	_lbl_floor_indicator.text = "1/2"
	_lbl_floor_indicator.custom_minimum_size = Vector2(46.0, 0.0)
	_lbl_floor_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_floor_indicator.add_theme_font_size_override("font_size", 13)
	_lbl_floor_indicator.add_theme_color_override("font_color", TEXT_PRIMARY)
	fl_hb.add_child(_lbl_floor_indicator)

	_btn_floor_up = Button.new()
	_btn_floor_up.text = "▲"
	_btn_floor_up.tooltip_text = "Subir un piso"
	_btn_floor_up.custom_minimum_size = Vector2(36.0, 32.0)
	_style_button(_btn_floor_up, false, false, 32.0)
	_btn_floor_up.pressed.connect(func() -> void: EventBus.active_floor_step_requested.emit(1))
	fl_hb.add_child(_btn_floor_up)

	# --- NOTIFICACION / VALIDACION FLOTANTE ---
	_toast_panel = PanelContainer.new()
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_panel.offset_left = -270.0
	_toast_panel.offset_right = 270.0
	_toast_panel.offset_top = -54.0
	_toast_panel.offset_bottom = -16.0
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, BORDER_SUBTLE, 8, 8))
	_toast_panel.modulate.a = 0.0
	_gameplay_root.add_child(_toast_panel)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.add_theme_font_size_override("font_size", 12)
	_toast_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_child(_toast_label)

	# --- PESTANA DESPLEGABLE TRANSLUCIDA DERECHA (SOLO FLECHA ◀ / ▶, SIN NOMBRE DE TERMINAL) ---
	_xai_slide_wrapper = HBoxContainer.new()
	_xai_slide_wrapper.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_xai_slide_wrapper.offset_top = 84.0
	_xai_slide_wrapper.offset_bottom = -20.0
	_xai_slide_wrapper.offset_left = -XAI_TAB_WIDTH
	_xai_slide_wrapper.offset_right = XAI_DRAWER_WIDTH
	(_xai_slide_wrapper as HBoxContainer).add_theme_constant_override("separation", 0)
	_xai_slide_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameplay_root.add_child(_xai_slide_wrapper)

	var tab_align: VBoxContainer = VBoxContainer.new()
	tab_align.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_align.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xai_slide_wrapper.add_child(tab_align)

	_btn_xai_tab = Button.new()
	_btn_xai_tab.text = "◀"
	_btn_xai_tab.tooltip_text = "Desplegar / ocultar registro de pasos"
	_btn_xai_tab.custom_minimum_size = Vector2(XAI_TAB_WIDTH, 76.0)
	_btn_xai_tab.add_theme_font_size_override("font_size", 14)
	_btn_xai_tab.add_theme_color_override("font_color", TEXT_PRIMARY)
	_btn_xai_tab.add_theme_stylebox_override("normal", _create_button_style(BG_XAI_GLASS, BORDER_SUBTLE, 8, 2.0, 4.0))
	_btn_xai_tab.add_theme_stylebox_override("hover", _create_button_style(BG_ELEVATED, BORDER_FOCUS, 8, 2.0, 4.0))
	_btn_xai_tab.add_theme_stylebox_override("pressed", _create_button_style(BG_ACTIVE_ACCENT, BORDER_FOCUS, 8, 2.0, 4.0))
	_btn_xai_tab.pressed.connect(_toggle_xai_drawer)
	tab_align.add_child(_btn_xai_tab)

	var xai_panel: PanelContainer = PanelContainer.new()
	xai_panel.custom_minimum_size = Vector2(XAI_DRAWER_WIDTH, 0.0)
	xai_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	xai_panel.add_theme_stylebox_override("panel", _create_panel_style(BG_XAI_GLASS, BORDER_SUBTLE, 10, 10))
	_xai_slide_wrapper.add_child(xai_panel)

	var xai_box: Control = Control.new()
	xai_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xai_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	xai_panel.add_child(xai_box)

	_xai_log_label = RichTextLabel.new()
	_xai_log_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xai_log_label.bbcode_enabled = true
	_xai_log_label.scroll_following = true
	_xai_log_label.selection_enabled = true
	_xai_log_label.add_theme_font_size_override("normal_font_size", 11)
	_xai_log_label.add_theme_stylebox_override("normal", _create_panel_style(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0, 4))
	xai_box.add_child(_xai_log_label)

	var btn_xai_clr: Button = Button.new()
	btn_xai_clr.text = "⌫"
	btn_xai_clr.tooltip_text = "Limpiar registro"
	btn_xai_clr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn_xai_clr.offset_left = -30.0
	btn_xai_clr.offset_top = 0.0
	btn_xai_clr.offset_right = 0.0
	btn_xai_clr.offset_bottom = 28.0
	_style_button(btn_xai_clr, false, false, 28.0)
	btn_xai_clr.pressed.connect(_clear_xai_log)
	xai_box.add_child(btn_xai_clr)

	# --- MENU DESPLEGABLE IZQUIERDO (COMPACTO, ICONOS + TOOLTIPS TRANSLUCIDOS) ---
	_drawer_panel = PanelContainer.new()
	_drawer_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_drawer_panel.offset_left = -DRAWER_WIDTH - 24.0
	_drawer_panel.offset_right = -24.0
	_drawer_panel.offset_top = 80.0
	_drawer_panel.offset_bottom = -16.0
	_drawer_panel.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, BORDER_SUBTLE, 12, 12))
	_gameplay_root.add_child(_drawer_panel)

	var drawer_scroll: ScrollContainer = ScrollContainer.new()
	drawer_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	drawer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drawer_panel.add_child(drawer_scroll)

	var dvbox: VBoxContainer = VBoxContainer.new()
	dvbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dvbox.add_theme_constant_override("separation", 10)
	drawer_scroll.add_child(dvbox)

	# Municion compacta (solo icono y numero)
	_lbl_inventory_status = Label.new()
	_lbl_inventory_status.text = "↗ 1   ·   ◆ No"
	_lbl_inventory_status.tooltip_text = "Flechas del agente y estado del Oro"
	_lbl_inventory_status.mouse_filter = Control.MOUSE_FILTER_PASS
	_lbl_inventory_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_inventory_status.add_theme_font_size_override("font_size", 12)
	_lbl_inventory_status.add_theme_color_override("font_color", Color(0.22, 0.74, 0.97))
	dvbox.add_child(_lbl_inventory_status)

	# 1. Herramientas de Construccion (grilla compacta de 2 cols con tooltips translucidos)
	var tool_grid: GridContainer = GridContainer.new()
	tool_grid.columns = 2
	tool_grid.add_theme_constant_override("h_separation", 6)
	tool_grid.add_theme_constant_override("v_separation", 6)
	dvbox.add_child(tool_grid)

	var tool_defs: Array[Dictionary] = [
		{"tool": GameConstants.GodTool.TOGGLE_PIT, "label": "◉ Pozo", "tip": "Colocar o quitar Pozo (emite brisa).\nClic derecho rapido borra cualquier objeto."},
		{"tool": GameConstants.GodTool.TOGGLE_WUMPUS, "label": "▲ Wumpus", "tip": "Colocar o quitar Wumpus (multiples permitidos)."},
		{"tool": GameConstants.GodTool.TOGGLE_WALL, "label": "■ Muro", "tip": "Colocar o quitar Muro fisico impasable."},
		{"tool": GameConstants.GodTool.MOVE_GOLD, "label": "◆ Oro", "tip": "Colocar o quitar el Lingote de Oro (requerido para iniciar)."},
		{"tool": GameConstants.GodTool.TOGGLE_PORTAL, "label": "◎ Portal", "tip": "1er clic: Portal Azul · 2do clic: Portal Naranja (mismo piso)."},
		{"tool": GameConstants.GodTool.TOGGLE_STAIRS, "label": "▤ Escalera", "tip": "1er clic: inicio · Cambia de piso y 2do clic: destino libre."},
		{"tool": GameConstants.GodTool.TOGGLE_ARROW, "label": "↗ Flecha", "tip": "Colocar flecha recogible para abatir multiples Wumpus."},
		{"tool": GameConstants.GodTool.CLEAR_CELL, "label": "✕ Borrar", "tip": "Limpiar celda (tambien puedes usar Clic Derecho rapido)."}
	]
	for td: Dictionary in tool_defs:
		var t_enum: GameConstants.GodTool = td["tool"] as GameConstants.GodTool
		var btn: Button = Button.new()
		btn.text = String(td["label"])
		btn.tooltip_text = String(td["tip"])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(btn, t_enum == _active_tool, false, 34.0)
		btn.pressed.connect(func() -> void: EventBus.god_tool_changed.emit(t_enum))
		tool_grid.add_child(btn)
		_tool_buttons[int(t_enum)] = btn

	dvbox.add_child(_make_divider())

	# 2. Pisos (1 a 5) y Dimensiones
	var floor_manage_hbox: HBoxContainer = HBoxContainer.new()
	floor_manage_hbox.add_theme_constant_override("separation", 6)
	dvbox.add_child(floor_manage_hbox)

	_btn_add_floor = Button.new()
	_btn_add_floor.text = "+ Piso"
	_btn_add_floor.tooltip_text = "Anadir un nuevo piso superior (maximo 5 pisos)"
	_btn_add_floor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(_btn_add_floor, true, false, 32.0)
	_btn_add_floor.pressed.connect(func() -> void: EventBus.floor_add_requested.emit())
	floor_manage_hbox.add_child(_btn_add_floor)

	_lbl_floor_count_info = Label.new()
	_lbl_floor_count_info.text = "1/5"
	_lbl_floor_count_info.custom_minimum_size = Vector2(36.0, 0.0)
	_lbl_floor_count_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_floor_count_info.add_theme_font_size_override("font_size", 12)
	_lbl_floor_count_info.add_theme_color_override("font_color", TEXT_SECONDARY)
	floor_manage_hbox.add_child(_lbl_floor_count_info)

	_btn_remove_floor = Button.new()
	_btn_remove_floor.text = "- Piso"
	_btn_remove_floor.tooltip_text = "Eliminar el piso mas alto"
	_btn_remove_floor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(_btn_remove_floor, false, true, 32.0)
	_btn_remove_floor.pressed.connect(func() -> void: EventBus.floor_remove_requested.emit())
	floor_manage_hbox.add_child(_btn_remove_floor)

	var size_hbox: HBoxContainer = HBoxContainer.new()
	size_hbox.add_theme_constant_override("separation", 6)
	dvbox.add_child(size_hbox)
	for dim: int in [4, 6, 8]:
		var vec_size: Vector2i = Vector2i(dim, dim)
		var b_size: Button = Button.new()
		b_size.text = "%d×%d" % [dim, dim]
		b_size.tooltip_text = "Expandir conserva tus casillas · Reducir pedira confirmacion"
		b_size.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b_size, dim == 6, false, 30.0)
		b_size.pressed.connect(func() -> void: _on_size_button_clicked(vec_size))
		size_hbox.add_child(b_size)
		_size_buttons[vec_size] = b_size

	dvbox.add_child(_make_divider())

	# 3. Mapas Guardados (compacto)
	var save_row: HBoxContainer = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	dvbox.add_child(save_row)

	_map_name_input = LineEdit.new()
	_map_name_input.placeholder_text = "Nombre..."
	_map_name_input.tooltip_text = "Escribe un nombre y pulsa Guardar"
	_map_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_name_input.custom_minimum_size = Vector2(0.0, 32.0)
	_map_name_input.text_submitted.connect(func(txt: String) -> void:
		EventBus.map_save_requested.emit(txt)
		_map_name_input.release_focus()
	)
	save_row.add_child(_map_name_input)

	var btn_save_map: Button = Button.new()
	btn_save_map.text = "↓"
	btn_save_map.tooltip_text = "Guardar mapa actual"
	btn_save_map.custom_minimum_size = Vector2(38.0, 32.0)
	_style_button(btn_save_map, true, false, 32.0)
	btn_save_map.pressed.connect(func() -> void:
		EventBus.map_save_requested.emit(_map_name_input.text)
		_map_name_input.release_focus()
	)
	save_row.add_child(btn_save_map)

	_saved_maps_dropdown = OptionButton.new()
	_saved_maps_dropdown.tooltip_text = "Seleccionar mapa guardado"
	_saved_maps_dropdown.custom_minimum_size = Vector2(0.0, 30.0)
	dvbox.add_child(_saved_maps_dropdown)

	var load_row: HBoxContainer = HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 6)
	dvbox.add_child(load_row)

	var btn_load_map: Button = Button.new()
	btn_load_map.text = "↑"
	btn_load_map.tooltip_text = "Cargar mapa seleccionado"
	btn_load_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn_load_map, false, false, 30.0)
	btn_load_map.pressed.connect(_on_load_selected_map_pressed)
	load_row.add_child(btn_load_map)

	var btn_del_map: Button = Button.new()
	btn_del_map.text = "✕"
	btn_del_map.tooltip_text = "Eliminar mapa guardado seleccionado"
	btn_del_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn_del_map, false, true, 30.0)
	btn_del_map.pressed.connect(_on_delete_selected_map_pressed)
	load_row.add_child(btn_del_map)

	var btn_default_map: Button = Button.new()
	btn_default_map.text = "↺"
	btn_default_map.tooltip_text = "Restaurar escenario por defecto de fabrica"
	btn_default_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn_default_map, false, false, 30.0)
	btn_default_map.pressed.connect(func() -> void: EventBus.map_reset_default_requested.emit())
	load_row.add_child(btn_default_map)

	dvbox.add_child(_make_divider())

	# 4. Acciones de Simulacion y Navegacion (solo iconos compactos + tooltips)
	var sim_row: HBoxContainer = HBoxContainer.new()
	sim_row.add_theme_constant_override("separation", 6)
	dvbox.add_child(sim_row)

	var btn_step: Button = Button.new()
	btn_step.text = "⏭"
	btn_step.tooltip_text = "Avanzar exactamente 1 turno (N)"
	btn_step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn_step, false, false, 34.0)
	btn_step.pressed.connect(func() -> void: EventBus.sim_control_requested.emit("STEP"))
	sim_row.add_child(btn_step)

	_btn_speed_cycle = Button.new()
	_btn_speed_cycle.text = "1.0x"
	_btn_speed_cycle.tooltip_text = "Cambiar velocidad de animacion (0.5x / 1.0x / 2.0x)"
	_btn_speed_cycle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(_btn_speed_cycle, false, false, 34.0)
	_btn_speed_cycle.pressed.connect(_on_speed_cycle_pressed)
	sim_row.add_child(_btn_speed_cycle)

	var btn_reset_rot: Button = Button.new()
	btn_reset_rot.text = "0°"
	btn_reset_rot.tooltip_text = "Restablecer rotacion del tablero a 0 grados"
	btn_reset_rot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn_reset_rot, false, false, 34.0)
	btn_reset_rot.pressed.connect(func() -> void: EventBus.board_rotation_reset_requested.emit())
	sim_row.add_child(btn_reset_rot)

	var nav_row: HBoxContainer = HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 6)
	dvbox.add_child(nav_row)

	var btn_open_opt: Button = Button.new()
	btn_open_opt.text = "⚙"
	btn_open_opt.tooltip_text = "Abrir Opciones (PC y Mando)"
	btn_open_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn_open_opt, false, false, 34.0)
	btn_open_opt.pressed.connect(func() -> void:
		_return_screen = "GAMEPLAY"
		_set_screen("OPTIONS")
	)
	nav_row.add_child(btn_open_opt)

	var btn_main_menu: Button = Button.new()
	btn_main_menu.text = "⌂"
	btn_main_menu.tooltip_text = "Volver a la Pantalla de Inicio"
	btn_main_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn_main_menu, false, false, 34.0)
	btn_main_menu.pressed.connect(func() -> void: _set_screen("START_MENU"))
	nav_row.add_child(btn_main_menu)

# ==============================================================================
# 4. MODAL DE CONFIRMACION AL REDUCIR TAMANO DEL TABLERO
# ==============================================================================
func _build_shrink_confirm_modal() -> void:
	_shrink_confirm_overlay = ColorRect.new()
	_shrink_confirm_overlay.theme = _hud_theme
	_shrink_confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	(_shrink_confirm_overlay as ColorRect).color = BG_CANVAS_SCRIM
	_shrink_confirm_overlay.visible = false
	add_child(_shrink_confirm_overlay)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shrink_confirm_overlay.add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(380.0, 0.0)
	card.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, Color(0.97, 0.44, 0.44, 0.70), 12, 24))
	center.add_child(card)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	card.add_child(vb)

	_shrink_confirm_label = Label.new()
	_shrink_confirm_label.text = "¿Reducir el tablero? Se eliminaran las casillas fuera del nuevo limite."
	_shrink_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shrink_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shrink_confirm_label.add_theme_font_size_override("font_size", 13)
	_shrink_confirm_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	vb.add_child(_shrink_confirm_label)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	vb.add_child(btn_row)

	var btn_cancel: Button = Button.new()
	btn_cancel.text = "Cancelar"
	btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn_cancel, false, false, 38.0)
	btn_cancel.pressed.connect(func() -> void:
		_shrink_confirm_overlay.visible = false
		_pending_shrink_size = Vector2i.ZERO
	)
	btn_row.add_child(btn_cancel)

	var btn_accept: Button = Button.new()
	btn_accept.text = "Aceptar"
	btn_accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(btn_accept, false, true, 38.0)
	btn_accept.pressed.connect(func() -> void:
		var target_sz: Vector2i = _pending_shrink_size
		_shrink_confirm_overlay.visible = false
		_pending_shrink_size = Vector2i.ZERO
		if target_sz != Vector2i.ZERO:
			EventBus.board_resize_requested.emit(target_sz)
	)
	btn_row.add_child(btn_accept)

func _on_size_button_clicked(new_size: Vector2i) -> void:
	if new_size == _current_grid_size:
		return
	if new_size.x < _current_grid_size.x or new_size.y < _current_grid_size.y:
		# Pedir confirmacion antes de recortar casillas extra
		_pending_shrink_size = new_size
		_shrink_confirm_label.text = "Reducir el tablero de %d×%d a %d×%d borrara las casillas y objetos que queden fuera.\n¿Deseas continuar?" % [
			_current_grid_size.x, _current_grid_size.y, new_size.x, new_size.y
		]
		_shrink_confirm_overlay.visible = true
	else:
		# Expandir directamente sin borrar nada
		EventBus.board_resize_requested.emit(new_size)

# ==============================================================================
# ANIMACIONES DE DRAWERS, PANTALLAS Y PROBADOR EN VIVO
# ==============================================================================
func _set_screen(screen_name: String) -> void:
	_current_screen = screen_name
	_start_screen_overlay.visible = (screen_name == "START_MENU")
	_options_overlay.visible = (screen_name == "OPTIONS")
	_gameplay_root.visible = (screen_name == "GAMEPLAY")
	if screen_name != "GAMEPLAY" and _shrink_confirm_overlay != null:
		_shrink_confirm_overlay.visible = false
	GameConstants.is_gameplay_active = (screen_name == "GAMEPLAY")
	EventBus.app_screen_changed.emit(screen_name)

func _toggle_drawer() -> void:
	if _current_screen != "GAMEPLAY":
		return
	_is_drawer_open = not _is_drawer_open
	if _drawer_tween != null and _drawer_tween.is_valid():
		_drawer_tween.kill()

	var target_left: float = 16.0 if _is_drawer_open else (-DRAWER_WIDTH - 24.0)
	var target_right: float = (16.0 + DRAWER_WIDTH) if _is_drawer_open else -24.0
	_drawer_tween = create_tween()
	_drawer_tween.set_parallel(true)
	_drawer_tween.tween_property(_drawer_panel, "offset_left", target_left, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_drawer_tween.tween_property(_drawer_panel, "offset_right", target_right, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_style_icon_action_button(_btn_hud_menu, _is_drawer_open)

func _toggle_xai_drawer() -> void:
	if _current_screen != "GAMEPLAY":
		return
	_is_xai_open = not _is_xai_open
	if _xai_tween != null and _xai_tween.is_valid():
		_xai_tween.kill()

	var target_left: float = -(XAI_DRAWER_WIDTH + XAI_TAB_WIDTH + 12.0) if _is_xai_open else -XAI_TAB_WIDTH
	var target_right: float = -12.0 if _is_xai_open else XAI_DRAWER_WIDTH
	_xai_tween = create_tween()
	_xai_tween.set_parallel(true)
	_xai_tween.tween_property(_xai_slide_wrapper, "offset_left", target_left, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_xai_tween.tween_property(_xai_slide_wrapper, "offset_right", target_right, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_btn_xai_tab.text = "▶" if _is_xai_open else "◀"

func _process(_delta: float) -> void:
	if _current_screen != "OPTIONS":
		return
	_update_live_input_tester()

func _update_live_input_tester() -> void:
	var connected: Array[int] = Input.get_connected_joypads()
	if connected.is_empty():
		_lbl_joypad_detected.text = "Mandos: 0"
	else:
		_lbl_joypad_detected.text = "Mando: %s" % [Input.get_joy_name(connected[0])]

	for action_name: String in _test_pills.keys():
		var pill: PanelContainer = _test_pills[action_name] as PanelContainer
		var is_pressed_now: bool = Input.is_action_pressed(action_name) or bool(_vr_test_states.get(action_name, false))
		var bg: Color = BG_SUCCESS_PULSE if is_pressed_now else BG_SURFACE
		var brd: Color = BORDER_FOCUS if is_pressed_now else BORDER_SUBTLE
		pill.add_theme_stylebox_override("panel", _create_panel_style(bg, brd, 8, 8))

	var lx: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ly: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var rx: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)

	if Input.is_action_pressed("board_rotate_left"):
		rx = -1.0
	elif Input.is_action_pressed("board_rotate_right"):
		rx = 1.0
	if Input.is_action_pressed("board_tilt_up"):
		ry = -1.0
	elif Input.is_action_pressed("board_tilt_down"):
		ry = 1.0

	_lbl_left_stick_val.text = "Stick Izq: %.2f, %.2f" % [lx, ly]
	_lbl_right_stick_val.text = "Stick Der: %.2f, %.2f" % [rx, ry]
	_bar_lx.value = lx
	_bar_ly.value = ly
	_bar_rx.value = rx
	_bar_ry.value = ry

func _on_vr_input_test_pulse(action_name: String, pressed: bool) -> void:
	_vr_test_states[action_name] = pressed

func _start_listening_rebind(action_name: String, mode_str: String) -> void:
	_waiting_rebind_action = action_name
	_waiting_rebind_mode = mode_str
	_refresh_all_keybind_labels()
	if mode_str == "PC" and _pc_rebind_buttons.has(action_name):
		var btn: Button = _pc_rebind_buttons[action_name] as Button
		btn.text = "..."
		_style_button(btn, true, false, 32.0)
	elif mode_str == "GAMEPAD" and _gamepad_rebind_buttons.has(action_name):
		var btn_g: Button = _gamepad_rebind_buttons[action_name] as Button
		btn_g.text = "..."
		_style_button(btn_g, true, false, 32.0)

func _input(event: InputEvent) -> void:
	if _current_screen == "OPTIONS" and not _waiting_rebind_action.is_empty():
		if event is InputEventKey:
			var ke: InputEventKey = event as InputEventKey
			if ke.pressed and not ke.echo:
				if ke.keycode == KEY_ESCAPE:
					_waiting_rebind_action = ""
					_waiting_rebind_mode = ""
					_refresh_all_keybind_labels()
				elif _waiting_rebind_mode == "PC":
					var target_a: String = _waiting_rebind_action
					_waiting_rebind_action = ""
					_waiting_rebind_mode = ""
					PlatformManager.rebind_action_key(target_a, ke.keycode)
				get_viewport().set_input_as_handled()
		elif event is InputEventJoypadButton:
			var jb: InputEventJoypadButton = event as InputEventJoypadButton
			if jb.pressed and _waiting_rebind_mode == "GAMEPAD":
				var target_j: String = _waiting_rebind_action
				_waiting_rebind_action = ""
				_waiting_rebind_mode = ""
				PlatformManager.rebind_action_joypad(target_j, jb.button_index)
				get_viewport().set_input_as_handled()
		return

	if _current_screen == "OPTIONS" and event is InputEventKey:
		var k_esc: InputEventKey = event as InputEventKey
		if k_esc.pressed and not k_esc.echo and k_esc.keycode == KEY_ESCAPE:
			_set_screen(_return_screen)
			get_viewport().set_input_as_handled()

func _refresh_all_keybind_labels() -> void:
	for act_name: String in _pc_rebind_buttons.keys():
		var btn: Button = _pc_rebind_buttons[act_name] as Button
		btn.text = PlatformManager.get_pc_key_label(act_name)
		_style_button(btn, _waiting_rebind_mode == "PC" and act_name == _waiting_rebind_action, false, 32.0)

	for act_name: String in _gamepad_rebind_buttons.keys():
		var btn_g: Button = _gamepad_rebind_buttons[act_name] as Button
		btn_g.text = PlatformManager.get_gamepad_button_label(act_name)
		_style_button(btn_g, _waiting_rebind_mode == "GAMEPAD" and act_name == _waiting_rebind_action, false, 32.0)

	if _lbl_hud_menu_key != null:
		_lbl_hud_menu_key.text = PlatformManager.get_action_short_badge("action_menu")
	if _lbl_hud_play_key != null:
		_lbl_hud_play_key.text = PlatformManager.get_action_short_badge("action_primary")
	if _lbl_hud_stop_key != null:
		_lbl_hud_stop_key.text = PlatformManager.get_action_short_badge("action_back")

func _show_toast(msg: String, is_error: bool = false) -> void:
	if _toast_panel == null or _toast_label == null or msg.is_empty():
		return
	_toast_label.text = msg
	if is_error:
		_toast_panel.add_theme_stylebox_override("panel", _create_panel_style(BG_DANGER_SUBTLE, Color(0.97, 0.44, 0.44, 0.85), 8, 8))
		_toast_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.86))
	else:
		_toast_panel.add_theme_stylebox_override("panel", _create_panel_style(BG_SURFACE, BORDER_FOCUS, 8, 8))
		_toast_label.add_theme_color_override("font_color", TEXT_PRIMARY)

	_toast_panel.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.8 if is_error else 1.6)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.4)

func _on_speed_cycle_pressed() -> void:
	_speed_index = (_speed_index + 1) % SPEED_OPTIONS.size()
	var mult: float = SPEED_OPTIONS[_speed_index]
	if _btn_speed_cycle != null:
		_btn_speed_cycle.text = "%.1fx" % [mult]
	EventBus.sim_speed_changed.emit(mult)

func _highlight_active_tool(tool_id: GameConstants.GodTool) -> void:
	_active_tool = tool_id
	for key: int in _tool_buttons.keys():
		var btn: Button = _tool_buttons[key] as Button
		_style_button(btn, key == int(tool_id), false, 34.0)

func _on_god_tool_changed(new_tool: GameConstants.GodTool) -> void:
	_highlight_active_tool(new_tool)
	if _current_screen == "GAMEPLAY" and not _is_drawer_open:
		_show_toast(GameConstants.get_tool_display_name(new_tool), false)

func _on_sim_state_changed(new_state: GameConstants.SimState, _status_message: String) -> void:
	_current_sim_state = new_state
	if _lbl_hud_play_icon != null:
		_lbl_hud_play_icon.text = "⏸" if new_state == GameConstants.SimState.RUNNING else "▶"

func _on_agent_inventory_updated(arrow_count: int, has_gold: bool) -> void:
	if _lbl_inventory_status != null:
		_lbl_inventory_status.text = "↗ %d   ·   ◆ %s" % [arrow_count, "OK" if has_gold else "—"]

func _on_active_floor_changed(active_fl: int, total_floors: int) -> void:
	_active_floor = active_fl
	_floor_count = total_floors
	_update_floor_controls()

func _update_floor_controls() -> void:
	var has_multi: bool = (_floor_count >= 2)
	if _floor_bar_panel != null:
		_floor_bar_panel.visible = has_multi
	if _lbl_floor_indicator != null:
		_lbl_floor_indicator.text = "%d/%d" % [_active_floor + 1, _floor_count]
	if _btn_floor_down != null:
		_btn_floor_down.disabled = (_active_floor <= 0)
	if _btn_floor_up != null:
		_btn_floor_up.disabled = (_active_floor >= _floor_count - 1)
	if _lbl_floor_count_info != null:
		_lbl_floor_count_info.text = "%d/%d" % [_floor_count, GameConstants.MAX_FLOORS]
	if _btn_remove_floor != null:
		_btn_remove_floor.disabled = (_floor_count <= 1)

func _on_world_truth_changed(truth_snapshot: Dictionary) -> void:
	var g_size: Vector2i = truth_snapshot.get("grid_size", GameConstants.DEFAULT_GRID_SIZE) as Vector2i
	_current_grid_size = g_size
	for k: Vector2i in _size_buttons.keys():
		var b: Button = _size_buttons[k] as Button
		_style_button(b, k == g_size, false, 30.0)

func _on_saved_maps_list_updated(map_names: Array[String], status_msg: String) -> void:
	if _saved_maps_dropdown == null:
		return
	_saved_maps_dropdown.clear()
	if map_names.is_empty():
		_saved_maps_dropdown.add_item("—")
		_saved_maps_dropdown.disabled = true
	else:
		_saved_maps_dropdown.disabled = false
		for m: String in map_names:
			_saved_maps_dropdown.add_item(m)
	if not status_msg.is_empty():
		_show_toast(status_msg, status_msg.begins_with("No ") or status_msg.begins_with("Error"))

func _on_load_selected_map_pressed() -> void:
	if _saved_maps_dropdown == null or _saved_maps_dropdown.disabled or _saved_maps_dropdown.selected < 0:
		return
	var map_name: String = _saved_maps_dropdown.get_item_text(_saved_maps_dropdown.selected)
	EventBus.map_load_requested.emit(map_name)

func _on_delete_selected_map_pressed() -> void:
	if _saved_maps_dropdown == null or _saved_maps_dropdown.disabled or _saved_maps_dropdown.selected < 0:
		return
	var map_name: String = _saved_maps_dropdown.get_item_text(_saved_maps_dropdown.selected)
	EventBus.map_delete_requested.emit(map_name)

func _on_xai_rule_triggered(turn_number: int, rule_code: String, message: String) -> void:
	var color_hex: String = "#38BDF8"
	if rule_code.begins_with("R1") or rule_code.begins_with("R2") or rule_code.begins_with("R3") or rule_code == "CSP-SAFE":
		color_hex = "#4ADE80"
	elif rule_code.begins_with("R4"):
		color_hex = "#FACC15"
	elif rule_code.begins_with("R5") or rule_code.begins_with("R6") or rule_code.begins_with("CSP-") or rule_code == "FATAL":
		color_hex = "#F87171"
	elif rule_code.begins_with("R7") or rule_code == "VICTORY" or rule_code == "ARROW":
		color_hex = "#FBBF24"
	elif rule_code == "PORTAL" or rule_code == "ESCALERA" or rule_code == "LINK":
		color_hex = "#22D3EE"
	elif rule_code.begins_with("R8") or rule_code.begins_with("VAL") or rule_code.begins_with("WAIT"):
		color_hex = "#FB923C"

	var line: String = "[color=#71717A][T%02d][/color] [b][color=%s][%s][/color][/b] %s" % [
		turn_number, color_hex, rule_code, message
	]
	_append_log_line(line)

func _on_xai_cbr_triggered(turn_number: int, similarity: float, chosen_cell: Vector2i, reason: String) -> void:
	var line: String = "[color=#71717A][T%02d][/color] [b][color=#60A5FA][RBC %.2f -> %s][/color][/b] %s" % [
		turn_number, similarity, str(chosen_cell), reason
	]
	_append_log_line(line)

func _append_log_line(bbcode_line: String) -> void:
	_log_entries.append(bbcode_line)
	if _log_entries.size() > 180:
		_log_entries.pop_front()
	if _xai_log_label != null:
		_xai_log_label.text = "\n".join(_log_entries)

func _clear_xai_log() -> void:
	_log_entries.clear()
	if _xai_log_label != null:
		_xai_log_label.text = ""
