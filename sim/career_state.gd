class_name CareerState
extends RefCounted

## Minimal headless Season & Career state manager.
##
## STATE TRANSACTION RULES:
## 1. Temporary / Non-Mutating Operations:
##    - `build_match_context(...)` creates a detached MatchContext copy from current roster + committed practice.
##    - `PhaseResolver.resolve_match(ctx)` and `PhaseResolver.apply_series_fatigue(ctx, report)` mutate ONLY
##      the temporary `MatchContext` and return a `MatchReport`. They NEVER mutate `CareerState`.
##    - `simulate_temporary_match(...)` and `simulate_temporary_series(...)` run on detached contexts
##      and leave `season_number`, `current_week`, `roster`, `standings`, and `match_history` untouched.
## 2. Explicit Commit Operations:
##    - `commit_practice_selections()` locks staged weekly drills (`PracticePlan.committed = true`).
##    - `commit_series_result(series_summary)` (or `commit_single_match_result(...)`) explicitly writes
##      win/loss standings, post-series player fatigue & tilt, and match history into the Season.
##    - `advance_week()` increments `current_week`, clears weekly drills, and applies weekly rest recovery.

const MatchContextScript = preload("res://sim/match_context.gd")
const MatchReportScript = preload("res://sim/match_report.gd")
const PhaseResolverScript = preload("res://sim/phase_resolver.gd")
const PracticePlanScript = preload("res://sim/practice_plan.gd")

const REQUIRED_PLAYER_ATTRIBUTES: Array[String] = [
	"macro",
	"micro",
	"multitask",
	"adapt",
	"clutch",
	"fatigue",
	"tilt",
	"default_civ_mastery"
]

var season_number: int = 1
var current_week: int = 1

# Deep-copied player records keyed by player_id
var roster: Dictionary = {}

# Team assignments: { team_id: Array[String] (player_ids) }
var teams: Dictionary = {}

# Staged (uncommitted) and committed weekly practice plans: { player_id: PracticePlan }
var staged_practice: Dictionary = {}
var committed_practice: Dictionary = {}

# Season standings keyed by team_id
var standings: Dictionary = {}

# Committed series/match records
var match_history: Array[Dictionary] = []

# Known valid content IDs for validation
var valid_civ_ids: Array[String] = []
var valid_map_ids: Array[String] = []
var valid_build_ids: Array[String] = []


func _init(
	p_players: Array = [],
	p_civs: Array = [],
	p_maps: Array = [],
	p_builds: Array = []
) -> void:
	if not p_players.is_empty():
		load_from_arrays(p_players, p_civs, p_maps, p_builds)
	else:
		load_from_data_dir()


func load_from_data_dir(
	players_path: String = "res://data/players.json",
	civs_path: String = "res://data/civs.json",
	maps_path: String = "res://data/maps.json",
	builds_path: String = "res://data/build_orders.json"
) -> bool:
	var players_arr: Array = PhaseResolverScript._read_json_array(players_path)
	var civs_arr: Array = PhaseResolverScript._read_json_array(civs_path)
	var maps_arr: Array = PhaseResolverScript._read_json_array(maps_path)
	var builds_arr: Array = PhaseResolverScript._read_json_array(builds_path)
	if players_arr.is_empty():
		return false
	load_from_arrays(players_arr, civs_arr, maps_arr, builds_arr)
	return true


func load_from_arrays(
	p_players: Array,
	p_civs: Array = [],
	p_maps: Array = [],
	p_builds: Array = []
) -> void:
	roster.clear()
	teams.clear()
	staged_practice.clear()
	committed_practice.clear()
	standings.clear()
	match_history.clear()
	valid_civ_ids.clear()
	valid_map_ids.clear()
	valid_build_ids.clear()

	for c in p_civs:
		if c is Dictionary and c.has("id"):
			valid_civ_ids.append(str(c["id"]))
	for m in p_maps:
		if m is Dictionary and m.has("id"):
			valid_map_ids.append(str(m["id"]))
	for b in p_builds:
		if b is Dictionary and b.has("id"):
			valid_build_ids.append(str(b["id"]))

	for p in p_players:
		if not (p is Dictionary) or not p.has("id"):
			continue
		var cloned: Dictionary = _deep_copy_player(p)
		var pid: String = str(cloned["id"])
		roster[pid] = cloned

		var tid: String = str(cloned.get("team_id", "unassigned"))
		if not teams.has(tid):
			teams[tid] = []
		(teams[tid] as Array).append(pid)

		if not standings.has(tid):
			standings[tid] = {
				"team_id": tid,
				"team_name": str(cloned.get("team_name", tid)),
				"series_wins": 0,
				"series_losses": 0,
				"game_wins": 0,
				"game_losses": 0
			}


static func _deep_copy_player(p: Dictionary) -> Dictionary:
	var copy: Dictionary = p.duplicate(true)
	for attr in REQUIRED_PLAYER_ATTRIBUTES:
		var raw_val: float = float(copy.get(attr, 50.0))
		if raw_val > 1.0:
			copy[attr] = clampf(raw_val, 0.0, 100.0)
		else:
			copy[attr] = clampf(raw_val * 100.0, 0.0, 100.0)
	if copy.get("civ_mastery") is Dictionary:
		copy["civ_mastery"] = (copy["civ_mastery"] as Dictionary).duplicate(true)
	else:
		copy["civ_mastery"] = {}
	return copy


## Validates that all players have valid attributes in [0, 100] and valid team assignments.
func validate_roster() -> Dictionary:
	var errors: Array[String] = []
	if roster.size() != 4:
		errors.append("Expected 4 players in roster, found %d" % roster.size())

	for pid in roster.keys():
		var p: Dictionary = roster[pid]
		if str(p.get("name", "")).is_empty():
			errors.append("Player %s missing name" % pid)
		if str(p.get("team_id", "")).is_empty():
			errors.append("Player %s missing team_id" % pid)
		for attr in REQUIRED_PLAYER_ATTRIBUTES:
			if not p.has(attr):
				errors.append("Player %s missing attribute %s" % [pid, attr])
				continue
			var val: float = float(p[attr])
			if val < 0.0 or val > 100.0:
				errors.append("Player %s attribute %s out of range [0, 100]: %f" % [pid, attr, val])
		var mastery_dict: Dictionary = p.get("civ_mastery", {})
		for cid in mastery_dict.keys():
			var mval: float = float(mastery_dict[cid])
			if mval < 0.0 or mval > 100.0:
				errors.append("Player %s civ_mastery[%s] out of range: %f" % [pid, str(cid), mval])

	return {
		"valid": errors.is_empty(),
		"player_count": roster.size(),
		"team_count": teams.size(),
		"errors": errors
	}


## Returns a detached copy of a player's dictionary so callers cannot mutate CareerState.roster.
func get_player_snapshot(player_id: String) -> Dictionary:
	if not roster.has(player_id):
		return {}
	return (roster[player_id] as Dictionary).duplicate(true)


## Returns the list of player IDs assigned to a given team.
func get_team_roster(team_id: String) -> Array[String]:
	var result: Array[String] = []
	var raw: Array = teams.get(team_id, [])
	for pid in raw:
		result.append(str(pid))
	return result


## Stages a weekly practice selection (civ, map, build) for a player without committing it yet.
func stage_practice(
	player_id: String,
	civ_id: String,
	map_id: String,
	build_id: String
) -> PracticePlan:
	if not roster.has(player_id):
		return null
	if not valid_civ_ids.is_empty() and not valid_civ_ids.has(civ_id):
		return null
	if not valid_map_ids.is_empty() and not valid_map_ids.has(map_id):
		return null
	if not valid_build_ids.is_empty() and not valid_build_ids.has(build_id):
		return null

	var plan := PracticePlanScript.new(player_id, civ_id, map_id, build_id, false)
	staged_practice[player_id] = plan
	return plan.duplicate_plan()


## Explicitly commits all staged weekly practice selections for the current week.
func commit_practice_selections() -> int:
	var count: int = 0
	for pid in staged_practice.keys():
		var plan: PracticePlan = staged_practice[pid]
		if plan != null and plan.is_complete():
			var locked := plan.duplicate_plan()
			locked.committed = true
			committed_practice[pid] = locked
			count += 1
	staged_practice.clear()
	return count


## Convenience method to stage and immediately commit a single player's weekly practice drill.
func set_and_commit_practice(
	player_id: String,
	civ_id: String,
	map_id: String,
	build_id: String
) -> PracticePlan:
	var staged := stage_practice(player_id, civ_id, map_id, build_id)
	if staged == null:
		return null
	var locked := staged.duplicate_plan()
	locked.committed = true
	committed_practice[player_id] = locked
	staged_practice.erase(player_id)
	return locked.duplicate_plan()


func get_committed_practice(player_id: String) -> PracticePlan:
	if not committed_practice.has(player_id):
		return null
	return (committed_practice[player_id] as PracticePlan).duplicate_plan()


## Constructs a completely detached MatchContext.SideConfig from the player's current career state
## and committed weekly practice. Modifying this SideConfig never mutates CareerState.
func build_side_config(
	player_id: String,
	civ_id: String,
	build_family_id: String,
	map_id: String
) -> MatchContext.SideConfig:
	var p: Dictionary = get_player_snapshot(player_id)
	var side := MatchContextScript.SideConfig.new()
	side.player_id = player_id
	side.player_name = str(p.get("name", player_id))
	side.macro = float(p.get("macro", 50.0))
	side.micro = float(p.get("micro", 50.0))
	side.multitask = float(p.get("multitask", 50.0))
	side.adapt = float(p.get("adapt", 50.0))
	side.clutch = float(p.get("clutch", 50.0))
	side.fatigue = float(p.get("fatigue", 0.0))
	side.tilt = float(p.get("tilt", 0.0))
	side.team_style = str(p.get("team_style", "balanced"))
	side.default_civ_mastery = float(p.get("default_civ_mastery", 50.0))
	if p.get("civ_mastery") is Dictionary:
		side.civ_mastery = (p["civ_mastery"] as Dictionary).duplicate(true)
	side.civ_id = civ_id
	side.build_family_id = build_family_id

	if committed_practice.has(player_id):
		var plan: PracticePlan = committed_practice[player_id]
		plan.apply_to_side_config(side, map_id)
	else:
		side.practiced_this_week = false

	return side


## Builds a detached MatchContext for a single game.
func build_match_context(
	player_a_id: String,
	civ_a_id: String,
	build_a_id: String,
	player_b_id: String,
	civ_b_id: String,
	build_b_id: String,
	map_id: String,
	seed_value: int = 1337
) -> MatchContext:
	var side_a := build_side_config(player_a_id, civ_a_id, build_a_id, map_id)
	var side_b := build_side_config(player_b_id, civ_b_id, build_b_id, map_id)
	return MatchContextScript.new(map_id, side_a, side_b, seed_value)


## Runs a temporary single-game simulation without mutating CareerState.
func simulate_temporary_match(
	resolver: PhaseResolver,
	player_a_id: String,
	civ_a_id: String,
	build_a_id: String,
	player_b_id: String,
	civ_b_id: String,
	build_b_id: String,
	map_id: String,
	seed_value: int = 1337
) -> MatchReport:
	var ctx := build_match_context(
		player_a_id,
		civ_a_id,
		build_a_id,
		player_b_id,
		civ_b_id,
		build_b_id,
		map_id,
		seed_value
	)
	return resolver.resolve_match(ctx)


## Runs a temporary Best-of-5 series simulation on detached state.
## Fatigue and tilt carry from game to game inside the temporary series,
## but CareerState itself is NOT modified unless `commit_series_result()` is explicitly called.
func simulate_temporary_series(
	resolver: PhaseResolver,
	player_a_id: String,
	player_b_id: String,
	games_setup: Array[Dictionary],
	base_seed: int = 5000,
	best_of: int = 5
) -> Dictionary:
	var wins_needed: int = int(floor(float(best_of) / 2.0)) + 1
	var wins_a: int = 0
	var wins_b: int = 0
	var game_reports: Array[Dictionary] = []

	# Detached series-level fatigue & tilt initialized from current CareerState snapshot
	var p_a: Dictionary = get_player_snapshot(player_a_id)
	var p_b: Dictionary = get_player_snapshot(player_b_id)
	var carry_fatigue_a: float = float(p_a.get("fatigue", 0.0))
	var carry_tilt_a: float = float(p_a.get("tilt", 0.0))
	var carry_fatigue_b: float = float(p_b.get("fatigue", 0.0))
	var carry_tilt_b: float = float(p_b.get("tilt", 0.0))

	var game_idx: int = 0
	for setup in games_setup:
		if wins_a >= wins_needed or wins_b >= wins_needed:
			break
		var map_id: String = str(setup.get("map_id", "sunbaked_expanse"))
		var civ_a_id: String = str(setup.get("civ_a_id", "valorian_march"))
		var build_a_id: String = str(setup.get("build_a_id", "mobile_flank_sweep"))
		var civ_b_id: String = str(setup.get("civ_b_id", "valorian_march"))
		var build_b_id: String = str(setup.get("build_b_id", "mobile_flank_sweep"))

		var ctx := build_match_context(
			player_a_id,
			civ_a_id,
			build_a_id,
			player_b_id,
			civ_b_id,
			build_b_id,
			map_id,
			base_seed + game_idx * 29
		)
		ctx.game_number = game_idx + 1
		ctx.series_best_of = best_of
		ctx.side_a.fatigue = carry_fatigue_a
		ctx.side_a.tilt = carry_tilt_a
		ctx.side_b.fatigue = carry_fatigue_b
		ctx.side_b.tilt = carry_tilt_b

		var report: MatchReport = resolver.resolve_match(ctx)
		if report.winner == "A":
			wins_a += 1
		else:
			wins_b += 1

		game_reports.append(report.to_dict())

		# Update temporary series carryover via PhaseResolver helper
		PhaseResolverScript.apply_series_fatigue(ctx, report)
		carry_fatigue_a = ctx.side_a.get_fatigue() * 100.0
		carry_tilt_a = ctx.side_a.get_tilt() * 100.0
		carry_fatigue_b = ctx.side_b.get_fatigue() * 100.0
		carry_tilt_b = ctx.side_b.get_tilt() * 100.0
		game_idx += 1

	var series_winner_side: String = "A" if wins_a >= wins_b else "B"
	var series_winner_player_id: String = player_a_id if series_winner_side == "A" else player_b_id

	return {
		"week": current_week,
		"player_a_id": player_a_id,
		"player_b_id": player_b_id,
		"wins_a": wins_a,
		"wins_b": wins_b,
		"winner_side": series_winner_side,
		"winner_player_id": series_winner_player_id,
		"post_series_state": {
			player_a_id: {
				"fatigue": carry_fatigue_a,
				"tilt": carry_tilt_a
			},
			player_b_id: {
				"fatigue": carry_fatigue_b,
				"tilt": carry_tilt_b
			}
		},
		"games": game_reports,
		"committed": false
	}


## Explicitly commits a finished series result into the Season state.
## Updates player fatigue/tilt, team standings, and match_history.
func commit_series_result(series_summary: Dictionary) -> bool:
	var player_a_id: String = str(series_summary.get("player_a_id", ""))
	var player_b_id: String = str(series_summary.get("player_b_id", ""))
	if not roster.has(player_a_id) or not roster.has(player_b_id):
		return false

	var post_state: Dictionary = series_summary.get("post_series_state", {})
	for pid in [player_a_id, player_b_id]:
		if post_state.has(pid) and roster.has(pid):
			var p_state: Dictionary = post_state[pid]
			roster[pid]["fatigue"] = clampf(float(p_state.get("fatigue", roster[pid]["fatigue"])), 0.0, 100.0)
			roster[pid]["tilt"] = clampf(float(p_state.get("tilt", roster[pid]["tilt"])), 0.0, 100.0)

	var team_a_id: String = str(roster[player_a_id].get("team_id", ""))
	var team_b_id: String = str(roster[player_b_id].get("team_id", ""))
	var wins_a: int = int(series_summary.get("wins_a", 0))
	var wins_b: int = int(series_summary.get("wins_b", 0))

	if standings.has(team_a_id):
		standings[team_a_id]["game_wins"] = int(standings[team_a_id]["game_wins"]) + wins_a
		standings[team_a_id]["game_losses"] = int(standings[team_a_id]["game_losses"]) + wins_b
		if wins_a > wins_b:
			standings[team_a_id]["series_wins"] = int(standings[team_a_id]["series_wins"]) + 1
		elif wins_b > wins_a:
			standings[team_a_id]["series_losses"] = int(standings[team_a_id]["series_losses"]) + 1

	if standings.has(team_b_id) and team_b_id != team_a_id:
		standings[team_b_id]["game_wins"] = int(standings[team_b_id]["game_wins"]) + wins_b
		standings[team_b_id]["game_losses"] = int(standings[team_b_id]["game_losses"]) + wins_a
		if wins_b > wins_a:
			standings[team_b_id]["series_wins"] = int(standings[team_b_id]["series_wins"]) + 1
		elif wins_a > wins_b:
			standings[team_b_id]["series_losses"] = int(standings[team_b_id]["series_losses"]) + 1

	var committed_record: Dictionary = series_summary.duplicate(true)
	committed_record["committed"] = true
	match_history.append(committed_record)
	return true


## Advances the Season to the next week, clearing weekly practice locks and applying rest recovery.
func advance_week(fatigue_recovery: float = 25.0, tilt_recovery: float = 20.0) -> void:
	current_week += 1
	staged_practice.clear()
	committed_practice.clear()
	for pid in roster.keys():
		var p: Dictionary = roster[pid]
		p["fatigue"] = clampf(float(p.get("fatigue", 0.0)) - fatigue_recovery, 0.0, 100.0)
		p["tilt"] = clampf(float(p.get("tilt", 0.0)) - tilt_recovery, 0.0, 100.0)


func to_dict() -> Dictionary:
	var serialized_staged: Dictionary = {}
	for pid in staged_practice.keys():
		serialized_staged[pid] = (staged_practice[pid] as PracticePlan).to_dict()

	var serialized_committed: Dictionary = {}
	for pid in committed_practice.keys():
		serialized_committed[pid] = (committed_practice[pid] as PracticePlan).to_dict()

	return {
		"season_number": season_number,
		"current_week": current_week,
		"roster": roster.duplicate(true),
		"teams": teams.duplicate(true),
		"staged_practice": serialized_staged,
		"committed_practice": serialized_committed,
		"standings": standings.duplicate(true),
		"match_history": match_history.duplicate(true)
	}
