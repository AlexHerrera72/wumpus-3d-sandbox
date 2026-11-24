class_name CellBeliefData
extends RefCounted
## Capa de Datos Puros: CellBeliefData
## Representa el estado epistemico individual de una celda Vector3i(x, y, floor)
## incluyendo enlaces especiales descubiertos (portales o escaleras) y riesgo
## probabilistico estimado por el solucionador CSP estilo Buscaminas.

var coords: Vector3i = Vector3i.ZERO
var visited: bool = false
var breeze: bool = false
var stench: bool = false
var glitter: bool = false
var is_wall: bool = false
var special_targets: Array[Vector3i] = []

var pit_state: int = GameConstants.FactState.UNKNOWN
var wumpus_state: int = GameConstants.FactState.UNKNOWN
var overall_state: int = GameConstants.OverallState.UNKNOWN

# Probabilidad exacta/estimada de peligro calculada por CSP Buscaminas [0.0 .. 1.0]
var pit_probability: float = 0.0
var wumpus_probability: float = 0.0
var pit_explained_by_confirmed: bool = false
var wumpus_explained_by_confirmed: bool = false

func _init(cell_coords: Vector3i = Vector3i.ZERO) -> void:
	coords = cell_coords

func reset_deductions_for_reconstruction() -> void:
	pit_probability = 0.0
	wumpus_probability = 0.0
	pit_explained_by_confirmed = false
	wumpus_explained_by_confirmed = false
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
		wumpus_state = GameConstants.FactState.UNKNOWN
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
