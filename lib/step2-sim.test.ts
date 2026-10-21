import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const matchContextGd = fs.readFileSync(path.join(process.cwd(), 'sim/match_context.gd'), 'utf8');
const matchReportGd = fs.readFileSync(path.join(process.cwd(), 'sim/match_report.gd'), 'utf8');
const phaseResolverGd = fs.readFileSync(path.join(process.cwd(), 'sim/phase_resolver.gd'), 'utf8');

test('Step 2 GDScript files exist, extend RefCounted, and have no SceneTree dependency', () => {
  const stripComments = (src: string) =>
    src
      .split('\n')
      .filter((line) => !line.trim().startsWith('#'))
      .join('\n');

  assert.match(matchContextGd, /class_name\s+MatchContext/);
  assert.match(matchContextGd, /extends\s+RefCounted/);
  assert.doesNotMatch(stripComments(matchContextGd), /get_tree\(|SceneTree|extends\s+Node/);

  assert.match(matchReportGd, /class_name\s+MatchReport/);
  assert.match(matchReportGd, /extends\s+RefCounted/);
  assert.doesNotMatch(stripComments(matchReportGd), /get_tree\(|SceneTree|extends\s+Node/);

  assert.match(phaseResolverGd, /class_name\s+PhaseResolver/);
  assert.match(phaseResolverGd, /extends\s+RefCounted/);
  assert.doesNotMatch(stripComments(phaseResolverGd), /get_tree\(|SceneTree|extends\s+Node/);
});

test('MatchContext holds all required stats, mastery, mental state, style, build, and prep fields', () => {
  for (const field of [
    'macro',
    'micro',
    'multitask',
    'adapt',
    'civ_mastery',
    'fatigue',
    'tilt',
    'clutch',
    'team_style',
    'build_family_id',
    'practiced_this_week',
    'has_prep_bonus',
  ]) {
    assert.ok(matchContextGd.includes(field), `Missing ${field} in match_context.gd`);
  }
});

test('MatchReport holds winner, win_probability, final_position_score, and phase event logs', () => {
  for (const field of [
    'var winner:',
    'var win_probability:',
    'var final_position_score:',
    'var event_logs:',
    '"phase": phase',
    '"text": text',
  ]) {
    assert.ok(matchReportGd.includes(field), `Missing ${field} in match_report.gd`);
  }
});

test('PhaseResolver implements 4-phase progression, +25% prep bonus, required events, sigmoid, and Bo5 fatigue helper', () => {
  assert.match(phaseResolverGd, /\["dark",\s*"feudal",\s*"castle",\s*"imp"\]/);
  assert.match(phaseResolverGd, /PREP_EXECUTION_BONUS:\s*float\s*=\s*0\.25/);
  assert.ok(phaseResolverGd.includes('build slipped'));
  assert.ok(phaseResolverGd.includes('fought under town center'));
  assert.ok(phaseResolverGd.includes('tech switch'));
  assert.ok(phaseResolverGd.includes('tilted after a throw'));
  assert.ok(phaseResolverGd.includes('func compute_win_probability('));
  assert.ok(phaseResolverGd.includes('func apply_series_fatigue('));
});
