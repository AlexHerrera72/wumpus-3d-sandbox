extends Node
## Autoload: PlatformManager
## Gestiona dos perfiles limpios e independientes que funcionan en paralelo:
##   1. Controles de PC (Teclado)
##   2. Mando General (4 Botones + 2 Joysticks, agnostico al dispositivo: Deck,
##      mando Xbox/PS, mando VR o cualquier gamepad conectado).
## Persiste ambas configuraciones en user://keybinds.cfg.

const KEYBINDS_CFG_PATH: String = "user://keybinds.cfg"
const KEYBINDS_KEY_SECTION: String = "pc_key_bindings"
const KEYBINDS_JOY_SECTION: String = "general_gamepad_bindings"

const DEFAULT_KEY_BINDINGS: Dictionary = {
	"action_primary": KEY_SPACE,
	"action_back": KEY_BACKSPACE,
	"action_menu": KEY_TAB,
	"action_aux": KEY_E,
	"board_rotate_left": KEY_LEFT,
	"board_rotate_right": KEY_RIGHT,
	"board_tilt_up": KEY_UP,
	"board_tilt_down": KEY_DOWN,
	"board_reset_rotation": KEY_HOME,
	"floor_up": KEY_PAGEUP,
	"floor_down": KEY_PAGEDOWN
}

const DEFAULT_JOY_BINDINGS: Dictionary = {
	"action_primary": JOY_BUTTON_A,
	"action_back": JOY_BUTTON_B,
	"action_menu": JOY_BUTTON_Y,
	"action_aux": JOY_BUTTON_X,
	"floor_up": JOY_BUTTON_RIGHT_SHOULDER,
	"floor_down": JOY_BUTTON_LEFT_SHOULDER,
	"board_reset_rotation": JOY_BUTTON_RIGHT_STICK
}

var active_rig_mode: GameConstants.ControlRigMode = GameConstants.ControlRigMode.PC_FREECAM
var is_xr_active: bool = false
var is_steam_deck_hardware: bool = false

var current_key_bindings: Dictionary = {} # String -> Key
var current_joy_bindings: Dictionary = {} # String -> JoyButton

func _ready() -> void:
	_setup_default_input_actions()
	_load_saved_keybinds()
	_detect_hardware_environment()
	_try_initialize_openxr()

func _setup_default_input_actions() -> void:
	current_key_bindings.clear()
	current_joy_bindings.clear()
	for action_name: String in DEFAULT_KEY_BINDINGS.keys():
		current_key_bindings[action_name] = DEFAULT_KEY_BINDINGS[action_name] as Key
	for action_name: String in DEFAULT_JOY_BINDINGS.keys():
		current_joy_bindings[action_name] = DEFAULT_JOY_BINDINGS[action_name] as JoyButton
	_rebuild_all_input_map_actions()

func _rebuild_all_input_map_actions() -> void:
	for action_name: String in DEFAULT_KEY_BINDINGS.keys():
		_apply_input_map_action(action_name)

func _apply_input_map_action(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	else:
		InputMap.action_erase_events(action_name)

	if current_key_bindings.has(action_name):
		var keycode: Key = current_key_bindings[action_name] as Key
		if keycode != KEY_NONE:
			var ev_key: InputEventKey = InputEventKey.new()
			ev_key.keycode = keycode
			InputMap.action_add_event(action_name, ev_key)

			if action_name == "board_reset_rotation" and keycode == KEY_HOME:
				var ev_zero: InputEventKey = InputEventKey.new()
				ev_zero.keycode = KEY_0
				InputMap.action_add_event(action_name, ev_zero)

	if current_joy_bindings.has(action_name):
		var joy_btn: JoyButton = current_joy_bindings[action_name] as JoyButton
		if int(joy_btn) >= 0:
			var ev_joy: InputEventJoypadButton = InputEventJoypadButton.new()
			ev_joy.button_index = joy_btn
			InputMap.action_add_event(action_name, ev_joy)

func rebind_action_key(action_name: String, new_keycode: Key) -> void:
	if not DEFAULT_KEY_BINDINGS.has(action_name):
		return
	current_key_bindings[action_name] = new_keycode
	_apply_input_map_action(action_name)
	_save_keybinds()
	EventBus.keybinds_updated.emit()

func rebind_action_joypad(action_name: String, new_joy_button: JoyButton) -> void:
	if not DEFAULT_KEY_BINDINGS.has(action_name):
		return
	current_joy_bindings[action_name] = new_joy_button
	_apply_input_map_action(action_name)
	_save_keybinds()
	EventBus.keybinds_updated.emit()

func reset_pc_keybinds() -> void:
	for action_name: String in DEFAULT_KEY_BINDINGS.keys():
		current_key_bindings[action_name] = DEFAULT_KEY_BINDINGS[action_name] as Key
	_rebuild_all_input_map_actions()
	_save_keybinds()
	EventBus.keybinds_updated.emit()

func reset_gamepad_keybinds() -> void:
	current_joy_bindings.clear()
	for action_name: String in DEFAULT_JOY_BINDINGS.keys():
		current_joy_bindings[action_name] = DEFAULT_JOY_BINDINGS[action_name] as JoyButton
	_rebuild_all_input_map_actions()
	_save_keybinds()
	EventBus.keybinds_updated.emit()

func reset_default_keybinds() -> void:
	_setup_default_input_actions()
	_save_keybinds()
	EventBus.keybinds_updated.emit()

func get_action_keycode(action_name: String) -> Key:
	return current_key_bindings.get(action_name, KEY_NONE) as Key

func get_action_joy_button(action_name: String) -> int:
	if not current_joy_bindings.has(action_name):
		return -1
	return int(current_joy_bindings[action_name])

func get_pc_key_label(action_name: String) -> String:
	var code: Key = get_action_keycode(action_name)
	if code == KEY_NONE:
		return "Sin asignar"
	return OS.get_keycode_string(code)

func get_gamepad_button_label(action_name: String) -> String:
	var joy_idx: int = get_action_joy_button(action_name)
	if joy_idx < 0:
		return "Sin asignar"
	return _joy_button_to_name(joy_idx as JoyButton)

func get_action_short_badge(action_name: String) -> String:
	var code: Key = get_action_keycode(action_name)
	var pc_badge: String = _key_to_short_badge(code)
	var joy_idx: int = get_action_joy_button(action_name)
	if joy_idx >= 0 and not Input.get_connected_joypads().is_empty():
		return "%s/%s" % [pc_badge, _joy_button_to_name(joy_idx as JoyButton)]
	return pc_badge

func _key_to_short_badge(code: Key) -> String:
	match code:
		KEY_SPACE:
			return "SPC"
		KEY_BACKSPACE:
			return "BKSP"
		KEY_TAB:
			return "TAB"
		KEY_ESCAPE:
			return "ESC"
		KEY_ENTER, KEY_KP_ENTER:
			return "ENT"
		KEY_LEFT:
			return "←"
		KEY_RIGHT:
			return "→"
		KEY_UP:
			return "↑"
		KEY_DOWN:
			return "↓"
		KEY_HOME:
			return "HM"
		KEY_PAGEUP:
			return "PG↑"
		KEY_PAGEDOWN:
			return "PG↓"
		KEY_NONE:
			return "—"
	var raw: String = OS.get_keycode_string(code)
	if raw.length() > 4:
		return raw.substr(0, 4).to_upper()
	return raw.to_upper()

func _joy_button_to_name(btn: JoyButton) -> String:
	match btn:
		JOY_BUTTON_A:
			return "Btn A"
		JOY_BUTTON_B:
			return "Btn B"
		JOY_BUTTON_X:
			return "Btn X"
		JOY_BUTTON_Y:
			return "Btn Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "L1"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "R1"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		JOY_BUTTON_START:
			return "START"
		JOY_BUTTON_BACK:
			return "SEL"
		JOY_BUTTON_DPAD_UP:
			return "D↑"
		JOY_BUTTON_DPAD_DOWN:
			return "D↓"
		JOY_BUTTON_DPAD_LEFT:
			return "D←"
		JOY_BUTTON_DPAD_RIGHT:
			return "D→"
	return "Btn %d" % [int(btn)]

func _save_keybinds() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	for action_name: String in current_key_bindings.keys():
		cfg.set_value(KEYBINDS_KEY_SECTION, action_name, int(current_key_bindings[action_name]))
	for action_name: String in current_joy_bindings.keys():
		cfg.set_value(KEYBINDS_JOY_SECTION, action_name, int(current_joy_bindings[action_name]))
	cfg.save(KEYBINDS_CFG_PATH)

func _load_saved_keybinds() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(KEYBINDS_CFG_PATH)
	if err != OK:
		return
	for action_name: String in DEFAULT_KEY_BINDINGS.keys():
		if cfg.has_section_key(KEYBINDS_KEY_SECTION, action_name):
			var saved_code: int = int(cfg.get_value(KEYBINDS_KEY_SECTION, action_name, int(DEFAULT_KEY_BINDINGS[action_name])))
			current_key_bindings[action_name] = saved_code as Key
		if cfg.has_section_key(KEYBINDS_JOY_SECTION, action_name):
			var saved_joy: int = int(cfg.get_value(KEYBINDS_JOY_SECTION, action_name, -1))
			if saved_joy >= 0:
				current_joy_bindings[action_name] = saved_joy as JoyButton
	_rebuild_all_input_map_actions()

func _detect_hardware_environment() -> void:
	var cmd_args: PackedStringArray = OS.get_cmdline_args()
	var processor_name: String = OS.get_processor_name().to_lower()
	var env_steam_deck: String = OS.get_environment("SteamDeck")
	if env_steam_deck == "1" or processor_name.contains("custom apu 0405") or processor_name.contains("aerith") or processor_name.contains("sepia") or cmd_args.has("--steam-deck"):
		is_steam_deck_hardware = true

func _try_initialize_openxr() -> void:
	var cmd_args: PackedStringArray = OS.get_cmdline_args()
	if cmd_args.has("--no-vr"):
		_set_non_vr_default_mode()
		return

	var xr_interface: XRInterface = XRServer.find_interface("OpenXR")
	if xr_interface != null:
		if xr_interface.is_initialized() or xr_interface.initialize():
			get_viewport().use_xr = true
			is_xr_active = true
			active_rig_mode = GameConstants.ControlRigMode.VR_OPENXR
			return

	_set_non_vr_default_mode()

func _set_non_vr_default_mode() -> void:
	is_xr_active = false
	if is_steam_deck_hardware:
		active_rig_mode = GameConstants.ControlRigMode.STEAM_DECK_GYRO
	else:
		active_rig_mode = GameConstants.ControlRigMode.PC_FREECAM

func switch_rig_mode(new_mode: GameConstants.ControlRigMode) -> void:
	if new_mode == GameConstants.ControlRigMode.VR_OPENXR and not is_xr_active:
		var xr_interface: XRInterface = XRServer.find_interface("OpenXR")
		if xr_interface != null and xr_interface.initialize():
			get_viewport().use_xr = true
			is_xr_active = true
		else:
			EventBus.ui_notification_requested.emit("Visor OpenXR no conectado. Usando pantalla plana.", true)
			return

	active_rig_mode = new_mode
	EventBus.control_rig_switched.emit(active_rig_mode)
	EventBus.keybinds_updated.emit()
