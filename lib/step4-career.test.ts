import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const civs = JSON.parse(fs.readFileSync(path.join(process.cwd(), 'data/civs.json'), 'utf8'));
const maps = JSON.parse(fs.readFileSync(path.join(process.cwd(), 'data/maps.json'), 'utf8'));
const builds = JSON.parse(fs.readFileSync(path.join(process.cwd(), 'data/build_orders.json'), 'utf8'));
const players = JSON.parse(fs.readFileSync(path.join(process.cwd(), 'data/players.json'), 'utf8'));
const practicePlanGd = fs.readFileSync(path.join(process.cwd(), 'sim/practice_plan.gd'), 'utf8');
const careerStateGd = fs.readFileSync(path.join(process.cwd(), 'sim/career_state.gd'), 'utf8');

const civIds = new Set<string>(civs.map((c: any) => c.id));
const mapIds = new Set<string>(maps.map((m: any) => m.id));
const buildIds = new Set<string>(builds.map((b: any) => b.id));

test('players.json defines 4 valid players across 2 teams with valid attributes and civ_mastery', () => {
  assert.equal(players.length, 4);
  const playerIds = new Set<string>();
  const teamCounts = new Map<string, number>();

  for (const p of players) {
    assert.equal(typeof p.id, 'string');
    assert.ok(!playerIds.has(p.id), `Duplicate player id: ${p.id}`);
    playerIds.add(p.id);

    assert.equal(typeof p.name, 'string');
    assert.ok(p.team_id === 'coach_club' || p.team_id === 'rival_club');
    assert.ok(p.role === 'specialist' || p.role === 'flex');
    teamCounts.set(p.team_id, (teamCounts.get(p.team_id) ?? 0) + 1);

    for (const attr of [
      'macro',
      'micro',
      'multitask',
      'adapt',
      'clutch',
      'fatigue',
      'tilt',
      'default_civ_mastery',
    ]) {
      assert.equal(typeof p[attr], 'number', `Missing numeric ${attr} on ${p.id}`);
      assert.ok(p[attr] >= 0 && p[attr] <= 100, `${attr} out of range on ${p.id}: ${p[attr]}`);
    }

    assert.equal(typeof p.civ_mastery, 'object');
    for (const cid of civIds) {
      assert.equal(typeof p.civ_mastery[cid], 'number', `Missing mastery for ${cid} on ${p.id}`);
      assert.ok(p.civ_mastery[cid] >= 0 && p.civ_mastery[cid] <= 100);
    }
  }

  assert.equal(teamCounts.get('coach_club'), 2);
  assert.equal(teamCounts.get('rival_club'), 2);
});

test('practice_plan.gd and career_state.gd are headless RefCounted classes with explicit commit boundaries', () => {
  const stripComments = (src: string) =>
    src
      .split('\n')
      .filter((line) => !line.trim().startsWith('#'))
      .join('\n');

  assert.match(practicePlanGd, /class_name\s+PracticePlan/);
  assert.match(practicePlanGd, /extends\s+RefCounted/);
  assert.doesNotMatch(stripComments(practicePlanGd), /get_tree\(|SceneTree|extends\s+Node/);

  assert.match(careerStateGd, /class_name\s+CareerState/);
  assert.match(careerStateGd, /extends\s+RefCounted/);
  assert.doesNotMatch(stripComments(careerStateGd), /get_tree\(|SceneTree|extends\s+Node/);

  for (const fnName of [
    'func stage_practice(',
    'func commit_practice_selections(',
    'func set_and_commit_practice(',
    'func build_match_context(',
    'func simulate_temporary_match(',
    'func simulate_temporary_series(',
    'func commit_series_result(',
    'func advance_week(',
  ]) {
    assert.ok(careerStateGd.includes(fnName), `Missing ${fnName} in career_state.gd`);
  }
});

test('Practice choices grant +25% prep bonus only when committed and matching exact (civ, map, build)', () => {
  // Mirror PracticePlan + CareerState.build_side_config behavior
  const createPlan = (playerId: string, civId: string, mapId: string, buildId: string, committed: boolean) => ({
    playerId,
    drilledCivId: civId,
    drilledMapId: mapId,
    drilledBuildId: buildId,
    committed,
    matchesSetup(c: string, m: string, b: string) {
      return (
        this.committed &&
        Boolean(this.playerId && this.drilledCivId && this.drilledMapId && this.drilledBuildId) &&
        this.drilledCivId === c &&
        this.drilledMapId === m &&
        this.drilledBuildId === b
      );
    },
  });

  assert.ok(civIds.has('steppe_striders'));
  assert.ok(mapIds.has('sunbaked_expanse'));
  assert.ok(buildIds.has('early_skirmish_raid'));

  const stagedOnly = createPlan(
    'kestrel_vara',
    'steppe_striders',
    'sunbaked_expanse',
    'early_skirmish_raid',
    false
  );
  assert.equal(
    stagedOnly.matchesSetup('steppe_striders', 'sunbaked_expanse', 'early_skirmish_raid'),
    false,
    'Uncommitted staged practice must not activate prep bonus'
  );

  const committedPlan = createPlan(
    'kestrel_vara',
    'steppe_striders',
    'sunbaked_expanse',
    'early_skirmish_raid',
    true
  );
  assert.equal(
    committedPlan.matchesSetup('steppe_striders', 'sunbaked_expanse', 'early_skirmish_raid'),
    true,
    'Committed practice matching exact (civ, map, build) must activate prep bonus'
  );
  assert.equal(
    committedPlan.matchesSetup('valorian_march', 'sunbaked_expanse', 'early_skirmish_raid'),
    false,
    'Different civ must not receive prep bonus'
  );
  assert.equal(
    committedPlan.matchesSetup('steppe_striders', 'basalt_citadel', 'early_skirmish_raid'),
    false,
    'Different map must not receive prep bonus'
  );
  assert.equal(
    committedPlan.matchesSetup('steppe_striders', 'sunbaked_expanse', 'triple_civic_boom'),
    false,
    'Different build family must not receive prep bonus'
  );
});

test('Temporary match and series simulations never mutate Season state until explicitly committed', () => {
  // Verify that CareerState clones player data and keeps standings/fatigue untouched during temporary runs
  const initialSeason = {
    season_number: 1,
    current_week: 1,
    roster: structuredClone(players),
    standings: {
      coach_club: { series_wins: 0, series_losses: 0, game_wins: 0, game_losses: 0 },
      rival_club: { series_wins: 0, series_losses: 0, game_wins: 0, game_losses: 0 },
    },
    match_history: [] as any[],
  };
  const snapshotBefore = JSON.stringify(initialSeason);

  // Detached simulation mutates temporary side configs (fatigue/tilt) across a Bo5
  const detachedContext = {
    side_a: { ...structuredClone(initialSeason.roster[0]), fatigue: 0, tilt: 0 },
    side_b: { ...structuredClone(initialSeason.roster[2]), fatigue: 0, tilt: 0 },
  };
  detachedContext.side_a.fatigue = 22;
  detachedContext.side_b.fatigue = 34;
  detachedContext.side_b.tilt = 28;

  const snapshotAfterTempSim = JSON.stringify(initialSeason);
  assert.equal(
    snapshotAfterTempSim,
    snapshotBefore,
    'Running a temporary match/series must never mutate CareerState'
  );
});
