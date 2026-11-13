class_name RigSwitcher
extends Node3D
## Sistema Multi-Camara: RigSwitcher
## Instancia y conmuta en vivo entre los 3 modos de camara y control:
## F1 -> RigPC_FreeCam | F2 -> RigDeck_Gyro | Auto/F3 -> RigVR_Quest.

var rig_pc: RigPC_FreeCam
var rig_deck: RigDeck_Gyro
var rig_vr: RigVR_Quest

func _ready() -> void:
	rig_pc = RigPC_FreeCam.new()
	rig_pc.name = "RigPC_FreeCam"
	add_child(rig_pc)

	rig_deck = RigDeck_Gyro.new()
	rig_deck.name = "RigDeck_Gyro"
	add_child(rig_deck)

	rig_vr = RigVR_Quest.new()
	rig_vr.name = "RigVR_Quest"
	add_child(rig_vr)

	EventBus.control_rig_switched.connect(_on_control_rig_switched)
	_apply_rig_mode(PlatformManager.active_rig_mode)

func _on_control_rig_switched(new_mode: GameConstants.ControlRigMode) -> void:
	_apply_rig_mode(new_mode)

func _apply_rig_mode(mode: GameConstants.ControlRigMode) -> void:
	if rig_pc != null:
		rig_pc.set_rig_active(mode == GameConstants.ControlRigMode.PC_FREECAM)
	if rig_deck != null:
		rig_deck.set_rig_active(mode == GameConstants.ControlRigMode.STEAM_DECK_GYRO)
	if rig_vr != null:
		rig_vr.set_rig_active(mode == GameConstants.ControlRigMode.VR_OPENXR)

func recalibrate_deck_gyro() -> void:
	if rig_deck != null:
		rig_deck.recalibrate_gyro()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke: InputEventKey = event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		if ke.keycode == KEY_F1:
			PlatformManager.switch_rig_mode(GameConstants.ControlRigMode.PC_FREECAM)
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_F2:
			PlatformManager.switch_rig_mode(GameConstants.ControlRigMode.STEAM_DECK_GYRO)
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_F3:
			PlatformManager.switch_rig_mode(GameConstants.ControlRigMode.VR_OPENXR)
			get_viewport().set_input_as_handled()
