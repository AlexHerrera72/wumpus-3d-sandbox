class_name MainSandbox
extends Node3D
## Ensamblador Principal: MainSandbox
## Script raiz auto-contenido que construye la iluminacion 3D (WorldEnvironment y
## DirectionalLight3D) e instancia automaticamente SandboxBoard3D, RigSwitcher,
## HUD_Controller y SimulationManager sin acoplamiento directo entre ellos.

var simulation_manager: SimulationManager
var sandbox_board: SandboxBoard3D
var rig_switcher: RigSwitcher
var hud_controller: HUD_Controller

func _ready() -> void:
	_setup_lighting_and_environment()
	_instantiate_subsystems()

func _setup_lighting_and_environment() -> void:
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "SandboxWorldEnvironment"

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.063, 0.078)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.74, 0.84)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)

	var sun_light: DirectionalLight3D = DirectionalLight3D.new()
	sun_light.name = "KeyDirectionalLight3D"
	sun_light.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun_light.light_color = Color(0.98, 0.96, 0.92)
	sun_light.light_energy = 1.25
	sun_light.shadow_enabled = true
	add_child(sun_light)

	var fill_light: DirectionalLight3D = DirectionalLight3D.new()
	fill_light.name = "FillDirectionalLight3D"
	fill_light.rotation_degrees = Vector3(-32.0, 145.0, 0.0)
	fill_light.light_color = Color(0.55, 0.72, 0.95)
	fill_light.light_energy = 0.38
	fill_light.shadow_enabled = false
	add_child(fill_light)

func _instantiate_subsystems() -> void:
	sandbox_board = SandboxBoard3D.new()
	sandbox_board.name = "SandboxBoard3D"
	add_child(sandbox_board)

	rig_switcher = RigSwitcher.new()
	rig_switcher.name = "RigSwitcher"
	add_child(rig_switcher)

	hud_controller = HUD_Controller.new()
	hud_controller.name = "HUD_Controller"
	add_child(hud_controller)

	simulation_manager = SimulationManager.new()
	simulation_manager.name = "SimulationManager"
	add_child(simulation_manager)
