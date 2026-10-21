class_name PhaseResolver
extends RefCounted

## Headless 4-phase RTS match resolver (dark -> feudal -> castle -> imp).
## Skills reduce mistakes; they never add bonus damage.
## Returns a MatchReport and never writes to disk.

const PHASES: Array[String] = ["dark", "feudal", "castle", "imp"]
const PREP_EXECUTION_BONUS: float = 0.25 # +25% execution boost when practiced this week
const CLOSE_GAME_THRESHOLD: float = 0.85 # Position band where clutch tightens variance
const SIGMOID_SLOPE: float = 1.65

var civs_by_id: Dictionary = {}
var maps_by_id: Dictionary = {}
var builds_by_id: Dictionary = {}


func _init(
	p_civs: Array = [],
	p_maps: Array = [],
	p_builds: Array = []
) -> void:
	if not p_civs.is_empty() or not p_maps.is_empty() or not p_builds.is_empty():
		load_from_arrays(p_civs, p_maps, p_builds)
	else:
		load_from_data_dir()


func load_from_data_dir(
	civs_path: String = "res://data/civs.json",
	maps_path: String = "res://data/maps.json",
	builds_path: String = "res://data/build_orders.json"
) -> bool:
	var civs_arr: Array = _read_json_array(civs_path)
	var maps_arr: Array = _read_json_array(maps_path)
	var builds_arr: Array = _read_json_array(builds_path)
	if civs_arr.is_empty() or maps_arr.is_empty() or builds_arr.is_empty():
		return false
	load_from_arrays(civs_arr, maps_arr, builds_arr)
	return true


func load_from_arrays(p_civs: Array, p_maps: Array, p_builds: Array) -> void:
	civs_by_id.clear()
	maps_by_id.clear()
	builds_by_id.clear()
	for c in p_civs:
		if c is Dictionary and c.has("id"):
			civs_by_id[str(c["id"])] = c
	for m in p_maps:
		if m is Dictionary and m.has("id"):
			maps_by_id[str(m["id"])] = m
	for b in p_builds:
		if b is Dictionary and b.has("id"):
			builds_by_id[str(b["id"])] = b


static func _read_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var raw_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Array:
		return parsed
	return []


## Resolves a single game across Dark -> Feudal -> Castle -> Imp and returns a MatchReport.
func resolve_match(ctx: MatchContext) -> MatchReport:
	var report := MatchReport.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ctx.seed_value)

	var map_data: Dictionary = maps_by_id.get(ctx.map_id, {
		"id": ctx.map_id,
		"name": ctx.map_id,
		"kind": "open",
		"favored_tags": []
	})
	var civ_a: Dictionary = civs_by_id.get(ctx.side_a.civ_id, {
		"id": ctx.side_a.civ_id,
		"name": ctx.side_a.civ_id,
		"tags": [],
		"power_spike": "castle"
	})
	var civ_b: Dictionary = civs_by_id.get(ctx.side_b.civ_id, {
		"id": ctx.side_b.civ_id,
		"name": ctx.side_b.civ_id,
		"tags": [],
		"power_spike": "castle"
	})
	var build_a: Dictionary = builds_by_id.get(ctx.side_a.build_family_id, {
		"id": ctx.side_a.build_family_id,
		"name": ctx.side_a.build_family_id,
		"map_kinds": ["open", "closed", "hybrid"],
		"beats": [],
		"loses_to": [],
		"timing": "castle",
		"execution_tax": 0.5
	})
	var build_b: Dictionary = builds_by_id.get(ctx.side_b.build_family_id, {
		"id": ctx.side_b.build_family_id,
		"name": ctx.side_b.build_family_id,
		"map_kinds": ["open", "closed", "hybrid"],
		"beats": [],
		"loses_to": [],
		"timing": "castle",
		"execution_tax": 0.5
	})

	var name_a: String = ctx.side_a.player_name if not ctx.side_a.player_name.is_empty() else "Side A"
	var name_b: String = ctx.side_b.player_name if not ctx.side_b.player_name.is_empty() else "Side B"

	# Track in-match dynamic tilt (starts at series tilt, can spike after a throw)
	var live_tilt_a: float = ctx.side_a.get_tilt()
	var live_tilt_b: float = ctx.side_b.get_tilt()

	# Track whether a countered player has already executed a mid-game tech switch
	var switched_a: bool = false
	var switched_b: bool = false
	var counter_dampener_a: float = 1.0
	var counter_dampener_b: float = 1.0

	var position_score: float = 0.0
	var peak_lead_a: float = 0.0
	var peak_lead_b: float = 0.0

	# Pre-compute base matchup counter direction (+1 if A beats B, -1 if B beats A, 0 neutral)
	var counter_edge: float = compute_build_counter_edge(build_a, build_b)

	for phase in PHASES:
		var phase_Prior: float = position_score
		var delta: float = 0.0

		# 1. Map & Civ Affinity (subtle structural edge in Dark/Feudal)
		var map_edge_a: float = _compute_map_fit(civ_a, build_a, map_data, phase)
		var map_edge_b: float = _compute_map_fit(civ_b, build_b, map_data, phase)
		var map_delta: float = map_edge_a - map_edge_b
		delta += map_delta

		if phase == "dark" and absf(map_delta) >= 0.14:
			var favored_name: String = name_a if map_delta > 0.0 else name_b
			report.add_event(phase, "%s secured a clean map-fit opening on %s" % [favored_name, str(map_data.get("name", ctx.map_id))])

		# 2. Build Counter & Adapt Tech Switch (Feudal, Castle, Imp)
		if phase != "dark" and counter_edge != 0.0:
			# Check if the countered side adapts via a tech switch in Castle or Imp
			if counter_edge < 0.0 and not switched_a and (phase == "castle" or phase == "imp"):
				if _try_tech_switch(ctx.side_a, live_tilt_a, rng):
					switched_a = true
					counter_dampener_a = 0.4
					report.add_event(phase, "%s executed a timely tech switch to blunt %s" % [name_a, str(build_b.get("name", build_b.get("id", "opponent plan")))])
			elif counter_edge > 0.0 and not switched_b and (phase == "castle" or phase == "imp"):
				if _try_tech_switch(ctx.side_b, live_tilt_b, rng):
					switched_b = true
					counter_dampener_b = 0.4
					report.add_event(phase, "%s executed a timely tech switch to blunt %s" % [name_b, str(build_a.get("name", build_a.get("id", "opponent plan")))])

			var phase_counter_weight: float = _get_phase_counter_weight(phase, build_a, build_b)
			var active_dampener: float = counter_dampener_a if counter_edge < 0.0 else counter_dampener_b
			var counter_delta: float = counter_edge * phase_counter_weight * active_dampener
			delta += counter_delta

			if phase == "feudal" and absf(counter_delta) >= 0.18:
				var counter_winner: String = name_a if counter_delta > 0.0 else name_b
				var winning_plan: String = str(build_a.get("name", build_a.get("id", ""))) if counter_delta > 0.0 else str(build_b.get("name", build_b.get("id", "")))
				report.add_event(phase, "%s gained counter leverage with %s" % [counter_winner, winning_plan])

		# 3. Civilization Power Spikes & Build Timings
		var spike_a: float = _compute_timing_spike(civ_a, build_a, ctx.side_a, phase)
		var spike_b: float = _compute_timing_spike(civ_b, build_b, ctx.side_b, phase)
		delta += (spike_a - spike_b)

		if spike_a - spike_b >= 0.22:
			report.add_event(phase, "%s hit a sharp %s power spike with %s" % [name_a, phase, str(civ_a.get("name", ctx.side_a.civ_id))])
		elif spike_b - spike_a >= 0.22:
			report.add_event(phase, "%s hit a sharp %s power spike with %s" % [name_b, phase, str(civ_b.get("name", ctx.side_b.civ_id))])

		# 4. Execution Error Scaling (Skills reduce mistakes; they NEVER add bonus damage)
		# Each side can only lose<=0 position from execution errors.
		var err_a: Dictionary = _evaluate_phase_execution(
			ctx.side_a,
			build_a,
			ctx.map_id,
			phase,
			live_tilt_a,
			rng
		)
		var err_b: Dictionary = _evaluate_phase_execution(
			ctx.side_b,
			build_b,
			ctx.map_id,
			phase,
			live_tilt_b,
			rng
		)

		# Mistakes hurt your own position: A's mistake reduces position_score, B's mistake increases position_score
		var mistake_penalty_a: float = float(err_a["penalty"])
		var mistake_penalty_b: float = float(err_b["penalty"])
		delta -= mistake_penalty_a
		delta += mistake_penalty_b

		if bool(err_a["build_slipped"]):
			report.add_event(phase, "%s build slipped under %s execution tax" % [name_a, phase])
		if bool(err_b["build_slipped"]):
			report.add_event(phase, "%s build slipped under %s execution tax" % [name_b, phase])

		if bool(err_a["fought_under_tc"]):
			report.add_event(phase, "%s fought under town center and bled army value" % name_a)
		if bool(err_b["fought_under_tc"]):
			report.add_event(phase, "%s fought under town center and bled army value" % name_b)

		# 5. Mental Variance & Throw / Tilt Check
		var mental_noise_a: float = rng.randfn(0.0, 0.05 + live_tilt_a * 0.14)
		var mental_noise_b: float = rng.randfn(0.0, 0.05 + live_tilt_b * 0.14)
		# Clamp mental upside so tilt never grants huge positive miracle swings
		mental_noise_a = minf(mental_noise_a, 0.06)
		mental_noise_b = minf(mental_noise_b, 0.06)
		delta += (mental_noise_a - mental_noise_b)

		position_score += delta
		report.phase_positions[phase] = position_score

		# Track peak leads and detect throws
		if phase_Prior >= 0.45 and delta <= -0.40:
			live_tilt_a = clampf(live_tilt_a + 0.22, 0.0, 1.0)
			report.threw_lead = true
			report.add_event(phase, "%s tilted after a throw in %s" % [name_a, phase])
		elif phase_Prior <= -0.45 and delta >= 0.40:
			live_tilt_b = clampf(live_tilt_b + 0.22, 0.0, 1.0)
			report.threw_lead = true
			report.add_event(phase, "%s tilted after a throw in %s" % [name_b, phase])

		peak_lead_a = maxf(peak_lead_a, position_score)
		peak_lead_b = maxf(peak_lead_b, -position_score)

	# 6. Close-game Clutch adjustment & Sigmoid Win Probability
	var final_pos: float = position_score
	if absf(final_pos) <= CLOSE_GAME_THRESHOLD:
		var clutch_diff: float = ctx.side_a.get_clutch() - ctx.side_b.get_clutch()
		var closeness_factor: float = 1.0 - (absf(final_pos) / CLOSE_GAME_THRESHOLD)
		# Clutch stabilizes nerve in close games and tightens variance
		var clutch_shift: float = clutch_diff * 0.35 * closeness_factor
		final_pos += clutch_shift
		if absf(clutch_shift) >= 0.08:
			var clutch_side: String = name_a if clutch_shift > 0.0 else name_b
			report.add_event("imp", "%s stayed composed in the clutch window" % clutch_side)

	report.final_position_score = final_pos
	report.win_probability = compute_win_probability(
		final_pos,
		ctx.side_a.get_clutch(),
		ctx.side_b.get_clutch()
	)

	# Determine winner using deterministic RNG roll against win_probability
	# In close games, higher combined clutch tightens the roll around the true edge
	var roll: float = rng.randf()
	if absf(final_pos) <= CLOSE_GAME_THRESHOLD:
		var avg_clutch: float = 0.5 * (ctx.side_a.get_clutch() + ctx.side_b.get_clutch())
		var compression: float = lerpf(1.0, 0.65, avg_clutch)
		roll = 0.5 + (roll - 0.5) * compression

	if roll <= report.win_probability:
		report.winner = "A"
		report.winner_index = 0
		report.winner_id = ctx.side_a.player_id if not ctx.side_a.player_id.is_empty() else "A"
		report.winner_probability = report.win_probability
	else:
		report.winner = "B"
		report.winner_index = 1
		report.winner_id = ctx.side_b.player_id if not ctx.side_b.player_id.is_empty() else "B"
		report.winner_probability = 1.0 - report.win_probability

	if (report.winner == "B" and peak_lead_a >= 0.55) or (report.winner == "A" and peak_lead_b >= 0.55):
		report.threw_lead = true

	return report


## Computes build counter relationship: +1.0 if build_a beats build_b, -1.0 if build_a loses_to build_b, 0.0 otherwise.
static func compute_build_counter_edge(build_a: Dictionary, build_b: Dictionary) -> float:
	var id_a: String = str(build_a.get("id", ""))
	var id_b: String = str(build_b.get("id", ""))
	if id_a.is_empty() or id_b.is_empty() or id_a == id_b:
		return 0.0
	var a_beats: Array = build_a.get("beats", [])
	var a_loses: Array = build_a.get("loses_to", [])
	if a_beats.has(id_b):
		return 1.0
	if a_loses.has(id_b):
		return -1.0
	return 0.0


## Evaluates execution mistakes for a single side in a single phase.
## Returns { "penalty": float >= 0.0, "build_slipped": bool, "fought_under_tc": bool, "effective_skill": float }
static func _evaluate_phase_execution(
	side: MatchContext.SideConfig,
	build: Dictionary,
	current_map_id: String,
	phase: String,
	live_tilt: float,
	rng: RandomNumberGenerator
) -> Dictionary:
	var tax: float = clampf(float(build.get("execution_tax", 0.5)), 0.0, 1.0)
	var macro: float = side.get_macro()
	var micro: float = side.get_micro()
	var multitask: float = side.get_multitask()
	var mastery: float = side.get_civ_mastery_for()
	var fatigue: float = side.get_fatigue()

	# Phase-weighted skill blend (macro anchors all phases; micro/multitask rise in Feudal/Castle/Imp)
	var base_skill: float = macro * 0.65 + mastery * 0.20 + micro * 0.08 + multitask * 0.07
	if phase == "feudal":
		base_skill = macro * 0.50 + micro * 0.25 + multitask * 0.12 + mastery * 0.13
	elif phase == "castle":
		base_skill = macro * 0.50 + micro * 0.20 + multitask * 0.17 + mastery * 0.13
	elif phase == "imp":
		base_skill = macro * 0.55 + multitask * 0.22 + micro * 0.10 + mastery * 0.13

	# Weekly preparation bonus (+25% if practiced this week on this civ, map, and plan)
	var prep_multiplier: float = 1.0 + PREP_EXECUTION_BONUS if side.has_prep_bonus(current_map_id) else 1.0
	var effective_skill: float = clampf(base_skill * prep_multiplier, 0.0, 1.25)

	# Execution deficit (0.0 at ceiling skill >= 1.0; higher deficit = more mistakes, never bonus damage)
	var execution_deficit: float = maxf(0.0, 1.0 - effective_skill)

	# Fatigue and tilt increase mistake pressure
	var stress_load: float = tax * (1.0 + fatigue * 0.55 + live_tilt * 0.65)
	if side.has_prep_bonus(current_map_id):
		stress_load *= (1.0 - PREP_EXECUTION_BONUS)

	# Mistake rate rises with execution deficit and stress load
	var raw_mistake_rate: float = clampf(
		0.02 + execution_deficit * 0.68 + (stress_load - effective_skill * 0.45) * 0.34,
		0.02,
		0.92
	)

	var penalty: float = 0.0
	var build_slipped: bool = false
	var fought_under_tc: bool = false

	# Deterministic continuous mistake drag (higher skill = smaller drag; 0 bonus damage at top skill)
	var baseline_drag: float = (
		execution_deficit * (0.52 + tax * 0.38)
		+ fatigue * 0.10
		+ live_tilt * 0.12
	) * 0.68
	penalty += baseline_drag

	# Discrete execution roll for build slip
	var slip_roll: float = rng.randf()
	if slip_roll < raw_mistake_rate:
		var slip_severity: float = 0.15 + (raw_mistake_rate - slip_roll) * 0.50
		penalty += slip_severity
		if slip_severity >= 0.16:
			build_slipped = true

	# Micro / Multitask engagement check in active combat phases (feudal & castle)
	if phase == "feudal" or phase == "castle":
		var combat_control: float = (micro * 0.55 + multitask * 0.45) * prep_multiplier
		var overextend_risk: float = clampf(
			0.05 + (tax * 0.32) + (live_tilt * 0.38) + (fatigue * 0.24) - (combat_control * 0.42),
			0.01,
			0.75
		)
		if rng.randf() < overextend_risk:
			penalty += 0.20 + live_tilt * 0.10
			fought_under_tc = true

	return {
		"penalty": penalty,
		"build_slipped": build_slipped,
		"fought_under_tc": fought_under_tc,
		"effective_skill": effective_skill
	}


static func _compute_map_fit(civ: Dictionary, build: Dictionary, map_data: Dictionary, phase: String) -> float:
	var map_kind: String = str(map_data.get("kind", "open"))
	var allowed_kinds: Array = build.get("map_kinds", [])
	var fit: float = 0.0

	# Map compatibility of the chosen build family
	if allowed_kinds.has(map_kind):
		fit += 0.07 if (phase == "dark" or phase == "feudal") else 0.04
	else:
		# Choosing a closed-only build on an open map (or vice versa) carries a heavy structural penalty
		fit -= 0.18 if (phase == "dark" or phase == "feudal") else 0.10

	# Civilization tag synergy with map favored_tags
	var civ_tags: Array = civ.get("tags", [])
	var favored_tags: Array = map_data.get("favored_tags", [])
	var match_count: int = 0
	for tag in civ_tags:
		if favored_tags.has(tag):
			match_count += 1

	if match_count > 0:
		fit += minf(0.10, float(match_count) * 0.05)
	return fit


static func _get_phase_counter_weight(phase: String, build_a: Dictionary, build_b: Dictionary) -> float:
	var weight: float = 0.18
	var timing_a: String = _normalize_phase_name(str(build_a.get("timing", "castle")))
	var timing_b: String = _normalize_phase_name(str(build_b.get("timing", "castle")))
	if phase == timing_a or phase == timing_b:
		weight += 0.14
	return weight


static func _compute_timing_spike(
	civ: Dictionary,
	build: Dictionary,
	side: MatchContext.SideConfig,
	phase: String
) -> float:
	var spike: float = 0.0
	var civ_spike: String = _normalize_phase_name(str(civ.get("power_spike", "castle")))
	var build_timing: String = _normalize_phase_name(str(build.get("timing", "castle")))
	var mastery: float = side.get_civ_mastery_for()

	if civ_spike == phase:
		# Mastery lets the player realize more of the civ's natural spike (up to 0.18)
		spike += 0.10 + mastery * 0.08
	if build_timing == phase:
		spike += 0.09
	if civ_spike == phase and build_timing == phase:
		# Aligned civ spike + build timing window
		spike += 0.05
	return spike


static func _normalize_phase_name(timing: String) -> String:
	if timing == "late":
		return "imp"
	return timing


static func _try_tech_switch(
	side: MatchContext.SideConfig,
	live_tilt: float,
	rng: RandomNumberGenerator
) -> bool:
	var adapt_skill: float = side.get_adapt()
	var multitask_skill: float = side.get_multitask()
	var switch_chance: float = clampf(
		adapt_skill * 0.65 + multitask_skill * 0.25 - live_tilt * 0.35 - side.get_fatigue() * 0.20,
		0.05,
		0.85
	)
	return rng.randf() < switch_chance


## Sigmoid win probability from final position score, with clutch tightening the slope in close games.
static func compute_win_probability(
	final_position_score: float,
	clutch_a: float = 0.5,
	clutch_b: float = 0.5
) -> float:
	var avg_clutch: float = clampf(0.5 * (clutch_a + clutch_b), 0.0, 1.0)
	var effective_slope: float = SIGMOID_SLOPE
	if absf(final_position_score) <= CLOSE_GAME_THRESHOLD:
		# Higher clutch steepens the curve slightly so small earned edges hold more reliably
		effective_slope = SIGMOID_SLOPE * (1.0 + avg_clutch * 0.25)
	var prob: float = 1.0 / (1.0 + exp(-effective_slope * final_position_score))
	return clampf(prob, 0.01, 0.99)


## Series fatigue & tilt helper: updates side_a and side_b in-place (and returns a summary Dictionary)
## after a game in a Best-of-5 series.
static func apply_series_fatigue(
	ctx: MatchContext,
	report: MatchReport
) -> Dictionary:
	var build_a_tax: float = 0.5
	var build_b_tax: float = 0.5
	var close_match: bool = absf(report.final_position_score) <= CLOSE_GAME_THRESHOLD
	var length_grind: float = 0.04 if close_match else 0.01

	var a_won: bool = report.winner == "A"

	# Winner accumulates base fatigue and sheds a small amount of tilt
	# Loser accumulates heavier fatigue and gains tilt (amplified if they threw a lead)
	var fatigue_delta_a: float = (0.07 if a_won else 0.11) + length_grind + build_a_tax * 0.02
	var fatigue_delta_b: float = (0.11 if a_won else 0.07) + length_grind + build_b_tax * 0.02

	var tilt_delta_a: float = -0.06 if a_won else (0.18 if report.threw_lead else 0.10)
	var tilt_delta_b: float = (0.18 if report.threw_lead else 0.10) if a_won else -0.06

	ctx.side_a.fatigue = clampf(ctx.side_a.get_fatigue() + fatigue_delta_a, 0.0, 1.0)
	ctx.side_b.fatigue = clampf(ctx.side_b.get_fatigue() + fatigue_delta_b, 0.0, 1.0)

	ctx.side_a.tilt = clampf(ctx.side_a.get_tilt() + tilt_delta_a, 0.0, 1.0)
	ctx.side_b.tilt = clampf(ctx.side_b.get_tilt() + tilt_delta_b, 0.0, 1.0)

	ctx.game_number += 1

	return {
		"game_number": ctx.game_number,
		"side_a": {
			"fatigue": ctx.side_a.fatigue,
			"tilt": ctx.side_a.tilt
		},
		"side_b": {
			"fatigue": ctx.side_b.fatigue,
			"tilt": ctx.side_b.tilt
		}
	}
