class_name MatchReport
extends RefCounted

## Immutable-by-convention value report returned by PhaseResolver.
## Never writes to disk or mutates save files.

var winner: String = "" # "A" or "B"
var winner_index: int = -1 # 0 for side_a, 1 for side_b
var winner_id: String = ""
var win_probability: float = 0.5 # Side A win probability in [0.0, 1.0]
var winner_probability: float = 0.5 # Winning side probability in [0.0, 1.0]
var final_position_score: float = 0.0 # Signed position score (> 0 favors A, < 0 favors B)
var phase_positions: Dictionary = {
	"dark": 0.0,
	"feudal": 0.0,
	"castle": 0.0,
	"imp": 0.0
}
var event_logs: Array[Dictionary] = []
var threw_lead: bool = false


func add_event(phase: String, text: String) -> void:
	event_logs.append({
		"phase": phase,
		"text": text
	})


func get_events_for_phase(phase: String) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for entry in event_logs:
		if str(entry.get("phase", "")) == phase:
			filtered.append(entry)
	return filtered


func to_dict() -> Dictionary:
	var serialized_logs: Array[Dictionary] = []
	for item in event_logs:
		serialized_logs.append({
			"phase": str(item.get("phase", "")),
			"text": str(item.get("text", ""))
		})
	return {
		"winner": winner,
		"winner_index": winner_index,
		"winner_id": winner_id,
		"win_probability": win_probability,
		"winner_probability": winner_probability,
		"final_position_score": final_position_score,
		"phase_positions": phase_positions.duplicate(),
		"event_logs": serialized_logs,
		"threw_lead": threw_lead
	}
