extends SceneTree

## Headless statistical balance harness for Wololo Desk.
## Invocation: godot --headless --path . --script res://sim/balance_harness.gd
## All test runner functions are static and callable without a SceneTree.

const MatchContextScript = preload("res://sim/match_context.gd")
const MatchReportScript = preload("res://sim/match_report.gd")
const PhaseResolverScript = preload("res://sim/phase_resolver.gd")

const DEFAULT_TRIALS: int = 200
const OPEN_MAP_ID: String = "sunbaked_expanse"
const SYMMETRIC_CIV_ID: String = "valorian_march"
const SYMMETRIC_BUILD_ID: String = "mobile_flank_sweep"
const PRESSURE_BUILD_ID: String = "early_skirmish_raid"
const BOOM_BUILD_ID: String = "triple_civic_boom"


func _initialize() -> void:
	var summary: Dictionary = run_all_tests()
	print_summary(summary)
	var exit_code: int = 0 if bool(summary.get("all_passed", false)) else 1
	quit(exit_code)


## Executes all three acceptance tests headlessly without requiring a SceneTree.
static func run_all_tests(resolver: PhaseResolver = null, trials: int = DEFAULT_TRIALS) -> Dictionary:
	var active_resolver: PhaseResolver = resolver
	if active_resolver == null:
		active_resolver = PhaseResolverScript.new()

	var test_a: Dictionary = run_test_a_macro_advantage(active_resolver, trials)
	var test_b: Dictionary = run_test_b_open_map_counter(active_resolver, trials)
	var test_c: Dictionary = run_test_c_bo5_fatigue_tilt(active_resolver, trials)

	var all_passed: bool = (
		bool(test_a.get("passed", false))
		and bool(test_b.get("passed", false))
		and bool(test_c.get("passed", false))
	)

	return {
		"test_a": test_a,
		"test_b": test_b,
		"test_c": test_c,
		"all_passed": all_passed
	}


## Test A — Large macro-skill advantage (90/100 vs 40/100 across 200 single-game trials).
## Target: 75% <= strong_player_win_rate <= 95%
static func run_test_a_macro_advantage(resolver: PhaseResolver, trials: int = DEFAULT_TRIALS) -> Dictionary:
	var strong_wins: int = 0
	var weak_wins: int = 0

	for i in range(trials):
		var side_a := MatchContextScript.SideConfig.new()
		side_a.player_id = "strong_macro"
		side_a.player_name = "Strong Macro (90)"
		side_a.macro = 90.0
		side_a.micro = 50.0
		side_a.multitask = 50.0
		side_a.adapt = 50.0
		side_a.clutch = 50.0
		side_a.fatigue = 0.0
		side_a.tilt = 0.0
		side_a.default_civ_mastery = 50.0
		side_a.civ_id = SYMMETRIC_CIV_ID
		side_a.build_family_id = SYMMETRIC_BUILD_ID
		side_a.practiced_this_week = false

		var side_b := MatchContextScript.SideConfig.new()
		side_b.player_id = "weak_macro"
		side_b.player_name = "Weak Macro (40)"
		side_b.macro = 40.0
		side_b.micro = 50.0
		side_b.multitask = 50.0
		side_b.adapt = 50.0
		side_b.clutch = 50.0
		side_b.fatigue = 0.0
		side_b.tilt = 0.0
		side_b.default_civ_mastery = 50.0
		side_b.civ_id = SYMMETRIC_CIV_ID
		side_b.build_family_id = SYMMETRIC_BUILD_ID
		side_b.practiced_this_week = false

		var seed_val: int = 10000 + i * 37
		var ctx := MatchContextScript.new(OPEN_MAP_ID, side_a, side_b, seed_val)
		var report: MatchReport = resolver.resolve_match(ctx)

		if report.winner == "A":
			strong_wins += 1
		else:
			weak_wins += 1

	var win_rate: float = float(strong_wins) / float(max(1, trials))
	var passed: bool = win_rate >= 0.75 and win_rate <= 0.95

	return {
		"name": "Test A — Large Macro-Skill Advantage (90 vs 40)",
		"trials": trials,
		"wins": strong_wins,
		"losses": weak_wins,
		"win_rate": win_rate,
		"target_text": "75.0% <= win_rate <= 95.0%",
		"passed": passed
	}


## Test B — Open-map strategy counter (early_skirmish_raid vs triple_civic_boom on sunbaked_expanse).
## Target: 58% <= pressure_player_win_rate <= 80%
static func run_test_b_open_map_counter(resolver: PhaseResolver, trials: int = DEFAULT_TRIALS) -> Dictionary:
	var pressure_wins: int = 0
	var boom_wins: int = 0

	var pressure_def: Dictionary = resolver.builds_by_id.get(PRESSURE_BUILD_ID, {})
	var boom_def: Dictionary = resolver.builds_by_id.get(BOOM_BUILD_ID, {})
	var counter_verified: bool = (
		(pressure_def.get("beats", []) as Array).has(BOOM_BUILD_ID)
		and (boom_def.get("loses_to", []) as Array).has(PRESSURE_BUILD_ID)
	)

	for i in range(trials):
		var side_a := MatchContextScript.SideConfig.new()
		side_a.player_id = "feudal_pressure"
		side_a.player_name = "Pressure Coach"
		side_a.macro = 50.0
		side_a.micro = 50.0
		side_a.multitask = 50.0
		side_a.adapt = 50.0
		side_a.clutch = 50.0
		side_a.fatigue = 0.0
		side_a.tilt = 0.0
		side_a.default_civ_mastery = 50.0
		side_a.civ_id = SYMMETRIC_CIV_ID
		side_a.build_family_id = PRESSURE_BUILD_ID
		side_a.practiced_this_week = false

		var side_b := MatchContextScript.SideConfig.new()
		side_b.player_id = "late_boom"
		side_b.player_name = "Boom Coach"
		side_b.macro = 50.0
		side_b.micro = 50.0
		side_b.multitask = 50.0
		side_b.adapt = 50.0
		side_b.clutch = 50.0
		side_b.fatigue = 0.0
		side_b.tilt = 0.0
		side_b.default_civ_mastery = 50.0
		side_b.civ_id = SYMMETRIC_CIV_ID
		side_b.build_family_id = BOOM_BUILD_ID
		side_b.practiced_this_week = false

		var seed_val: int = 20000 + i * 41
		var ctx := MatchContextScript.new(OPEN_MAP_ID, side_a, side_b, seed_val)
		var report: MatchReport = resolver.resolve_match(ctx)

		if report.winner == "A":
			pressure_wins += 1
		else:
			boom_wins += 1

	var win_rate: float = float(pressure_wins) / float(max(1, trials))
	var passed: bool = counter_verified and win_rate >= 0.58 and win_rate <= 0.80

	return {
		"name": "Test B — Open-Map Strategy Counter (%s vs %s)" % [PRESSURE_BUILD_ID, BOOM_BUILD_ID],
		"trials": trials,
		"wins": pressure_wins,
		"losses": boom_wins,
		"win_rate": win_rate,
		"counter_verified": counter_verified,
		"target_text": "58.0% <= win_rate <= 80.0%",
		"passed": passed
	}


## Test C — Fatigue (80/100) and Tilt (70/100) across 200 Best-of-5 series.
## Target: fatigued_player_series_win_rate < 45%
static func run_test_c_bo5_fatigue_tilt(resolver: PhaseResolver, series_count: int = DEFAULT_TRIALS) -> Dictionary:
	var fatigued_series_wins: int = 0
	var fresh_series_wins: int = 0

	for s in range(series_count):
		var side_a := MatchContextScript.SideConfig.new()
		side_a.player_id = "fatigued_side"
		side_a.player_name = "Fatigued Player"
		side_a.macro = 50.0
		side_a.micro = 50.0
		side_a.multitask = 50.0
		side_a.adapt = 50.0
		side_a.clutch = 50.0
		side_a.fatigue = 80.0
		side_a.tilt = 70.0
		side_a.default_civ_mastery = 50.0
		side_a.civ_id = SYMMETRIC_CIV_ID
		side_a.build_family_id = SYMMETRIC_BUILD_ID
		side_a.practiced_this_week = false

		var side_b := MatchContextScript.SideConfig.new()
		side_b.player_id = "fresh_side"
		side_b.player_name = "Fresh Player"
		side_b.macro = 50.0
		side_b.micro = 50.0
		side_b.multitask = 50.0
		side_b.adapt = 50.0
		side_b.clutch = 50.0
		side_b.fatigue = 0.0
		side_b.tilt = 0.0
		side_b.default_civ_mastery = 50.0
		side_b.civ_id = SYMMETRIC_CIV_ID
		side_b.build_family_id = SYMMETRIC_BUILD_ID
		side_b.practiced_this_week = false

		var ctx := MatchContextScript.new(OPEN_MAP_ID, side_a, side_b, 30000 + s * 100)
		ctx.series_best_of = 5

		var game_wins_a: int = 0
		var game_wins_b: int = 0
		var game_idx: int = 0

		while game_wins_a < 3 and game_wins_b < 3:
			# Reapply forced mental-state disadvantage (fatigue 80/100, tilt 70/100) before each game
			ctx.side_a.fatigue = 80.0
			ctx.side_a.tilt = 70.0
			ctx.seed_value = 30000 + s * 100 + game_idx * 17

			var report: MatchReport = resolver.resolve_match(ctx)
			if report.winner == "A":
				game_wins_a += 1
			else:
				game_wins_b += 1

			PhaseResolverScript.apply_series_fatigue(ctx, report)
			game_idx += 1

		if game_wins_a >= 3:
			fatigued_series_wins += 1
		else:
			fresh_series_wins += 1

	var series_win_rate: float = float(fatigued_series_wins) / float(max(1, series_count))
	var passed: bool = series_win_rate < 0.45

	return {
		"name": "Test C — Fatigue (80) & Tilt (70) Across Best-of-5 Series",
		"trials": series_count,
		"wins": fatigued_series_wins,
		"losses": fresh_series_wins,
		"win_rate": series_win_rate,
		"target_text": "series_win_rate < 45.0%",
		"passed": passed
	}


static func print_summary(summary: Dictionary) -> void:
	print("================================================================")
	print("WOLOLO DESK — HEADLESS BALANCE HARNESS (200 TRIALS PER TEST)")
	print("================================================================")
	for key in ["test_a", "test_b", "test_c"]:
		var res: Dictionary = summary.get(key, {})
		var status: String = "PASS" if bool(res.get("passed", false)) else "FAIL"
		var pct: float = float(res.get("win_rate", 0.0)) * 100.0
		print("[%s] %s" % [status, str(res.get("name", key))])
		print("  Record : %d W - %d L (%d total)" % [
			int(res.get("wins", 0)),
			int(res.get("losses", 0)),
			int(res.get("trials", 0))
		])
		print("  Rate   : %.1f%% (Target: %s)" % [pct, str(res.get("target_text", ""))])
	print("----------------------------------------------------------------")
	var overall: String = "ALL TESTS PASSED" if bool(summary.get("all_passed", false)) else "BALANCE HARNESS FAILED"
	print("OVERALL STATUS: %s" % overall)
	print("================================================================")
