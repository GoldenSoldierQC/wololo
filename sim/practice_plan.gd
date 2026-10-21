class_name PracticePlan
extends RefCounted

## Weekly drill assignment for a single player.
## Preparation bonus (+25%) applies ONLY when the match uses the exact
## (civ_id, map_id, build_family_id) tuple drilled during the week.

const MatchContextScript = preload("res://sim/match_context.gd")

var player_id: String = ""
var drilled_civ_id: String = ""
var drilled_map_id: String = ""
var drilled_build_id: String = ""
var committed: bool = false


func _init(
	p_player_id: String = "",
	p_civ_id: String = "",
	p_map_id: String = "",
	p_build_id: String = "",
	p_committed: bool = false
) -> void:
	player_id = p_player_id
	drilled_civ_id = p_civ_id
	drilled_map_id = p_map_id
	drilled_build_id = p_build_id
	committed = p_committed


func is_complete() -> bool:
	return (
		not player_id.is_empty()
		and not drilled_civ_id.is_empty()
		and not drilled_map_id.is_empty()
		and not drilled_build_id.is_empty()
	)


func matches_setup(civ_id: String, map_id: String, build_family_id: String) -> bool:
	if not committed or not is_complete():
		return false
	return (
		drilled_civ_id == civ_id
		and drilled_map_id == map_id
		and drilled_build_id == build_family_id
	)


func apply_to_side_config(side: MatchContext.SideConfig, current_map_id: String) -> void:
	if not committed or not is_complete():
		side.practiced_this_week = false
		side.drilled_civ_id = ""
		side.drilled_map_id = ""
		side.drilled_build_id = ""
		return

	side.drilled_civ_id = drilled_civ_id
	side.drilled_map_id = drilled_map_id
	side.drilled_build_id = drilled_build_id
	side.practiced_this_week = matches_setup(side.civ_id, current_map_id, side.build_family_id)


func duplicate_plan() -> PracticePlan:
	return PracticePlan.new(
		player_id,
		drilled_civ_id,
		drilled_map_id,
		drilled_build_id,
		committed
	)


func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"drilled_civ_id": drilled_civ_id,
		"drilled_map_id": drilled_map_id,
		"drilled_build_id": drilled_build_id,
		"committed": committed
	}


static func from_dict(data: Dictionary) -> PracticePlan:
	return PracticePlan.new(
		str(data.get("player_id", "")),
		str(data.get("drilled_civ_id", "")),
		str(data.get("drilled_map_id", "")),
		str(data.get("drilled_build_id", "")),
		bool(data.get("committed", false))
	)
