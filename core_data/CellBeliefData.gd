class_name CellBeliefData
extends RefCounted
## Capa de Datos Puros: CellBeliefData
## Representa el estado epistemico individual de una celda Vector2i(x, y)
## en la Base de Hechos del agente autonomo.

var coords: Vector2i = Vector2i.ZERO
var visited: bool = false
var breeze: bool = false
var stench: bool = false
var glitter: bool = false
var is_wall: bool = false

var pit_state: int = GameConstants.FactState.UNKNOWN
var wumpus_state: int = GameConstants.FactState.UNKNOWN
var overall_state: int = GameConstants.OverallState.UNKNOWN

func _init(cell_coords: Vector2i = Vector2i.ZERO) -> void:
	coords = cell_coords

func reset_deductions_for_reconstruction(wumpus_is_dead: bool) -> void:
	if is_wall:
		pit_state = GameConstants.FactState.SAFE
		wumpus_state = GameConstants.FactState.SAFE
		overall_state = GameConstants.OverallState.CONFIRMED_HAZARD
		return

	if visited:
		pit_state = GameConstants.FactState.SAFE
		wumpus_state = GameConstants.FactState.SAFE
		overall_state = GameConstants.OverallState.SAFE
	else:
		pit_state = GameConstants.FactState.UNKNOWN
		wumpus_state = GameConstants.FactState.SAFE if wumpus_is_dead else GameConstants.FactState.UNKNOWN
		overall_state = GameConstants.OverallState.UNKNOWN

func to_visual_state() -> GameConstants.CellVisualState:
	if is_wall or overall_state == GameConstants.OverallState.CONFIRMED_HAZARD:
		return GameConstants.CellVisualState.HAZARD_OR_WALL
	if visited and overall_state == GameConstants.OverallState.SAFE:
		return GameConstants.CellVisualState.VISITED_SAFE
	if overall_state == GameConstants.OverallState.SAFE:
		return GameConstants.CellVisualState.SAFE
	if overall_state == GameConstants.OverallState.SUSPICIOUS:
		return GameConstants.CellVisualState.SUSPICIOUS
	return GameConstants.CellVisualState.UNKNOWN
