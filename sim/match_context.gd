class_name MatchContext
extends RefCounted

## Holds all pre-match inputs for a single game in a series.
## Runs completely headless with no SceneTree dependency.


class SideConfig extends RefCounted:
	var player_id: String = ""
	var player_name: String = ""
	
	# Core skills (normalized 0.0 to 1.0; values > 1.0 are auto-normalized from 0..100 scale)
	var macro: float = 0.5
	var micro: float = 0.5
	var multitask: float = 0.5
	var adapt: float = 0.5
	var clutch: float = 0.5
	
	# Mental & physical state carried across a Best-of-5 series (0.0 to 1.0)
	var fatigue: float = 0.0
	var tilt: float = 0.0
	
	# Tactical identity & selection
	var team_style: String = "balanced" # aggressive | greedy | defensive | balanced
	var civ_id: String = ""
	var civ_mastery: Dictionary = {} # { civ_id: float (0.0..1.0) }
	var default_civ_mastery: float = 0.5
	var build_family_id: String = ""
	
	# Weekly preparation state
	var practiced_this_week: bool = false
	var drilled_civ_id: String = ""
	var drilled_map_id: String = ""
	var drilled_build_id: String = ""

	static func normalize_stat(value: float) -> float:
		if value > 1.0:
			return clampf(value / 100.0, 0.0, 1.0)
		return clampf(value, 0.0, 1.0)

	func get_macro() -> float:
		return normalize_stat(macro)

	func get_micro() -> float:
		return normalize_stat(micro)

	func get_multitask() -> float:
		return normalize_stat(multitask)

	func get_adapt() -> float:
		return normalize_stat(adapt)

	func get_clutch() -> float:
		return normalize_stat(clutch)

	func get_fatigue() -> float:
		return normalize_stat(fatigue)

	func get_tilt() -> float:
		return normalize_stat(tilt)

	func get_civ_mastery_for(target_civ_id: String = "") -> float:
		var cid: String = target_civ_id if not target_civ_id.is_empty() else civ_id
		if civ_mastery.has(cid):
			return normalize_stat(float(civ_mastery[cid]))
		return normalize_stat(default_civ_mastery)

	## Returns true if the player drilled this exact (civ, map, build_family) tuple this week
	## or if practiced_this_week is explicitly set without drill restrictions.
	func has_prep_bonus(current_map_id: String) -> bool:
		if not practiced_this_week:
			if not drilled_civ_id.is_empty() and not drilled_map_id.is_empty() and not drilled_build_id.is_empty():
				return (
					drilled_civ_id == civ_id
					and drilled_map_id == current_map_id
					and drilled_build_id == build_family_id
				)
			return false
		if not drilled_civ_id.is_empty() and drilled_civ_id != civ_id:
			return false
		if not drilled_map_id.is_empty() and drilled_map_id != current_map_id:
			return false
		if not drilled_build_id.is_empty() and drilled_build_id != build_family_id:
			return false
		return true

	func to_dict() -> Dictionary:
		return {
			"player_id": player_id,
			"player_name": player_name,
			"macro": get_macro(),
			"micro": get_micro(),
			"multitask": get_multitask(),
			"adapt": get_adapt(),
			"clutch": get_clutch(),
			"fatigue": get_fatigue(),
			"tilt": get_tilt(),
			"team_style": team_style,
			"civ_id": civ_id,
			"civ_mastery": civ_mastery.duplicate(),
			"default_civ_mastery": default_civ_mastery,
			"build_family_id": build_family_id,
			"practiced_this_week": practiced_this_week,
			"drilled_civ_id": drilled_civ_id,
			"drilled_map_id": drilled_map_id,
			"drilled_build_id": drilled_build_id
		}

	static func from_dict(data: Dictionary) -> SideConfig:
		var side := SideConfig.new()
		side.player_id = str(data.get("player_id", ""))
		side.player_name = str(data.get("player_name", side.player_id))
		side.macro = float(data.get("macro", 0.5))
		side.micro = float(data.get("micro", 0.5))
		side.multitask = float(data.get("multitask", 0.5))
		side.adapt = float(data.get("adapt", 0.5))
		side.clutch = float(data.get("clutch", 0.5))
		side.fatigue = float(data.get("fatigue", 0.0))
		side.tilt = float(data.get("tilt", 0.0))
		side.team_style = str(data.get("team_style", "balanced"))
		side.civ_id = str(data.get("civ_id", ""))
		if data.get("civ_mastery") is Dictionary:
			side.civ_mastery = data["civ_mastery"].duplicate()
		elif typeof(data.get("civ_mastery")) in [TYPE_FLOAT, TYPE_INT]:
			side.default_civ_mastery = float(data["civ_mastery"])
		side.default_civ_mastery = float(data.get("default_civ_mastery", side.default_civ_mastery))
		side.build_family_id = str(data.get("build_family_id", ""))
		side.practiced_this_week = bool(data.get("practiced_this_week", false))
		side.drilled_civ_id = str(data.get("drilled_civ_id", ""))
		side.drilled_map_id = str(data.get("drilled_map_id", ""))
		side.drilled_build_id = str(data.get("drilled_build_id", ""))
		return side


var map_id: String = ""
var game_number: int = 1
var series_best_of: int = 5
var seed_value: int = 1337
var side_a: SideConfig = SideConfig.new()
var side_b: SideConfig = SideConfig.new()


func _init(p_map_id: String = "", p_side_a: SideConfig = null, p_side_b: SideConfig = null, p_seed: int = 1337) -> void:
	map_id = p_map_id
	if p_side_a != null:
		side_a = p_side_a
	if p_side_b != null:
		side_b = p_side_b
	seed_value = p_seed


func to_dict() -> Dictionary:
	return {
		"map_id": map_id,
		"game_number": game_number,
		"series_best_of": series_best_of,
		"seed_value": seed_value,
		"side_a": side_a.to_dict(),
		"side_b": side_b.to_dict()
	}


static func from_dict(data: Dictionary) -> MatchContext:
	var ctx := MatchContext.new()
	ctx.map_id = str(data.get("map_id", ""))
	ctx.game_number = int(data.get("game_number", 1))
	ctx.series_best_of = int(data.get("series_best_of", 5))
	ctx.seed_value = int(data.get("seed_value", 1337))
	if data.get("side_a") is Dictionary:
		ctx.side_a = SideConfig.from_dict(data["side_a"])
	if data.get("side_b") is Dictionary:
		ctx.side_b = SideConfig.from_dict(data["side_b"])
	return ctx
