import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const VALID_TAGS = new Set(['archer', 'cav', 'infantry', 'siege', 'monk', 'naval']);
const VALID_SPIKES = new Set(['feudal', 'castle', 'imp', 'late']);
const VALID_MAP_KINDS = new Set(['open', 'closed', 'hybrid']);

const civs = JSON.parse(fs.readFileSync(path.join(process.cwd(), 'data/civs.json'), 'utf8'));
const maps = JSON.parse(fs.readFileSync(path.join(process.cwd(), 'data/maps.json'), 'utf8'));
const buildOrders = JSON.parse(fs.readFileSync(path.join(process.cwd(), 'data/build_orders.json'), 'utf8'));

test('civs.json has 8 original civs with valid tags and power_spike', () => {
  assert.equal(civs.length, 8);
  const ids = new Set<string>();
  for (const civ of civs) {
    assert.equal(typeof civ.id, 'string');
    assert.equal(typeof civ.name, 'string');
    assert.ok(!ids.has(civ.id), `Duplicate civ id: ${civ.id}`);
    ids.add(civ.id);
    assert.ok(Array.isArray(civ.tags) && civ.tags.length > 0);
    for (const tag of civ.tags) {
      assert.ok(VALID_TAGS.has(tag), `Invalid tag ${tag} on ${civ.id}`);
    }
    assert.ok(VALID_SPIKES.has(civ.power_spike), `Invalid power_spike ${civ.power_spike} on ${civ.id}`);
  }
});

test('maps.json has 4 maps with valid kind and favored_tags', () => {
  assert.equal(maps.length, 4);
  const ids = new Set<string>();
  for (const map of maps) {
    assert.equal(typeof map.id, 'string');
    assert.equal(typeof map.name, 'string');
    assert.ok(!ids.has(map.id), `Duplicate map id: ${map.id}`);
    ids.add(map.id);
    assert.ok(VALID_MAP_KINDS.has(map.kind), `Invalid map kind ${map.kind} on ${map.id}`);
    assert.ok(Array.isArray(map.favored_tags) && map.favored_tags.length > 0);
    for (const tag of map.favored_tags) {
      assert.ok(VALID_TAGS.has(tag), `Invalid favored_tag ${tag} on ${map.id}`);
    }
  }
});

test('build_orders.json has 8 plan families with symmetric counters and real counter cycles', () => {
  assert.equal(buildOrders.length, 8);
  const byId = new Map<string, (typeof buildOrders)[number]>();
  for (const plan of buildOrders) {
    assert.equal(typeof plan.id, 'string');
    assert.ok(!byId.has(plan.id), `Duplicate build order id: ${plan.id}`);
    byId.set(plan.id, plan);
    assert.ok(Array.isArray(plan.map_kinds) && plan.map_kinds.length > 0);
    for (const mk of plan.map_kinds) {
      assert.ok(VALID_MAP_KINDS.has(mk), `Invalid map_kind ${mk} on ${plan.id}`);
    }
    assert.ok(VALID_SPIKES.has(plan.timing), `Invalid timing ${plan.timing} on ${plan.id}`);
    assert.equal(typeof plan.execution_tax, 'number');
    assert.ok(plan.execution_tax >= 0 && plan.execution_tax <= 1);
    assert.ok(Array.isArray(plan.beats) && plan.beats.length > 0 && plan.beats.length < 7);
    assert.ok(Array.isArray(plan.loses_to) && plan.loses_to.length > 0);
  }

  // Verify bidirectional counter symmetry
  for (const plan of buildOrders) {
    for (const targetId of plan.beats) {
      const target = byId.get(targetId);
      assert.ok(target, `Unknown target ${targetId} in ${plan.id}.beats`);
      assert.ok(
        target.loses_to.includes(plan.id),
        `${plan.id} beats ${targetId}, but ${targetId}.loses_to does not include ${plan.id}`
      );
    }
    for (const counterId of plan.loses_to) {
      const counter = byId.get(counterId);
      assert.ok(counter, `Unknown counter ${counterId} in ${plan.id}.loses_to`);
      assert.ok(
        counter.beats.includes(plan.id),
        `${plan.id} loses_to ${counterId}, but ${counterId}.beats does not include ${plan.id}`
      );
    }
  }
});
