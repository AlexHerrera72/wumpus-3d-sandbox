extends Node
## Autoload: PlatformManager
## Detecta la plataforma de ejecucion (PC, Steam Deck o visor VR OpenXR),
## inicializa la sesion XR de forma segura y gestiona las teclas configurables
## de rotacion del tablero con persistencia en user://keybinds.cfg.

const KEYBINDS_CFG_PATH: String = "user://keybinds.cfg"
const KEYBINDS_SECTION: String = "board_rotation_keys"

const DEFAULT_BOARD_KEYBINDS: Dictionary = {
	"board_rotate_left": KEY_LEFT,
	"board_rotate_right": KEY_RIGHT,
	"board_tilt_up": KEY_UP,
	"board_tilt_down": KEY_DOWN,
	"board_reset_rotation": KEY_HOME
}

var active_rig_mode: GameConstants.ControlRigMode = GameConstants.ControlRigMode.PC_FREECAM
var is_xr_active: bool = false
var is_steam_deck_hardware: bool = false
var current_keybinds: Dictionary = {}

func _ready() -> void:
	_setup_default_board_input_actions()
	_load_saved_keybinds()
	_detect_hardware_environment()
	_try_initialize_openxr()

func _setup_default_board_input_actions() -> void:
	current_keybinds.clear()
	for action_name: String in DEFAULT_BOARD_KEYBINDS.keys():
		var default_key: Key = DEFAULT_BOARD_KEYBINDS[action_name] as Key
		current_keybinds[action_name] = default_key
		_apply_input_map_key(action_name, default_key)

func _apply_input_map_key(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	else:
		InputMap.action_erase_events(action_name)

	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = keycode
	InputMap.action_add_event(action_name, ev)

	# Para resetear rotacion, si la tecla asignada es KEY_HOME, agregamos tambien KEY_0 como respaldo comodo
	if action_name == "board_reset_rotation" and keycode == KEY_HOME:
		var ev_zero: InputEventKey = InputEventKey.new()
		ev_zero.keycode = KEY_0
		InputMap.action_add_event(action_name, ev_zero)

func rebind_action_key(action_name: String, new_keycode: Key) -> void:
	if not DEFAULT_BOARD_KEYBINDS.has(action_name):
		return
	current_keybinds[action_name] = new_keycode
	_apply_input_map_key(action_name, new_keycode)
	_save_keybinds()
	EventBus.keybinds_updated.emit()

func reset_default_keybinds() -> void:
	_setup_default_board_input_actions()
	_save_keybinds()
	EventBus.keybinds_updated.emit()

func get_action_keycode(action_name: String) -> Key:
	return current_keybinds.get(action_name, KEY_NONE) as Key

func get_action_key_label(action_name: String) -> String:
	var code: Key = get_action_keycode(action_name)
	if code == KEY_NONE:
		return "Ninguna"
	return OS.get_keycode_string(code)

func _save_keybinds() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	for action_name: String in current_keybinds.keys():
		cfg.set_value(KEYBINDS_SECTION, action_name, int(current_keybinds[action_name]))
	cfg.save(KEYBINDS_CFG_PATH)

func _load_saved_keybinds() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(KEYBINDS_CFG_PATH)
	if err != OK:
		return
	for action_name: String in DEFAULT_BOARD_KEYBINDS.keys():
		if cfg.has_section_key(KEYBINDS_SECTION, action_name):
			var saved_code: int = int(cfg.get_value(KEYBINDS_SECTION, action_name, int(DEFAULT_BOARD_KEYBINDS[action_name])))
			var key_enum: Key = saved_code as Key
			current_keybinds[action_name] = key_enum
			_apply_input_map_key(action_name, key_enum)

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
			EventBus.xai_rule_triggered.emit(
				0,
				"SYS-VR",
				"Visor OpenXR no detectado. Manteniendo modo pantalla plana."
			)
			return

	active_rig_mode = new_mode
	EventBus.control_rig_switched.emit(active_rig_mode)
