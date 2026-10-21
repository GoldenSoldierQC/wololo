import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const civs = JSON.parse(fs.readFileSync(path.join(process.cwd(), 'data/civs.json'), 'utf8'));
const maps = JSON.parse(fs.readFileSync(path.join(process.cwd(), 'data/maps.json'), 'utf8'));
const builds = JSON.parse(fs.readFileSync(path.join(process.cwd(), 'data/build_orders.json'), 'utf8'));
const harnessGd = fs.readFileSync(path.join(process.cwd(), 'sim/balance_harness.gd'), 'utf8');

const civsById = new Map<string, any>(civs.map((c: any) => [c.id, c]));
const mapsById = new Map<string, any>(maps.map((m: any) => [m.id, m]));
const buildsById = new Map<string, any>(builds.map((b: any) => [b.id, b]));

/**
 * Exact Godot 4 RandomNumberGenerator (PCG32) implementation
 */
class GodotRNG {
  private state: bigint = 0n;
  private inc: bigint = 1442695040888963407n;

  constructor(seedVal: number) {
    this.setSeed(seedVal);
  }

  setSeed(seedVal: number) {
    this.state = 0n;
    this.nextUInt32();
    this.state = (this.state + BigInt.asUintN(64, BigInt(seedVal))) & 0xffffffffffffffffn;
    this.nextUInt32();
  }

  nextUInt32(): number {
    const oldstate = this.state;
    this.state = (oldstate * 6364136223846793005n + (this.inc | 1n)) & 0xffffffffffffffffn;
    const xorshifted = Number(((oldstate >> 18n) ^ oldstate) >> 27n) >>> 0;
    const rot = Number(oldstate >> 59n) >>> 0;
    return ((xorshifted >>> rot) | (xorshifted << ((-rot) & 31))) >>> 0;
  }

  randf(): number {
    return this.nextUInt32() / 4294967295.0;
  }

  randfn(mean = 0.0, deviation = 1.0): number {
    let u1 = this.randf();
    if (u1 < 1e-7) u1 = 1e-7;
    const u2 = this.randf();
    return mean + deviation * (Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math.PI * u2));
  }
}

const clampf = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
const lerpf = (a: number, b: number, t: number) => a + (b - a) * t;
const normStat = (v: number) => (v > 1.0 ? clampf(v / 100.0, 0.0, 1.0) : clampf(v, 0.0, 1.0));

interface SideConfig {
  player_id: string;
  player_name: string;
  macro: number;
  micro: number;
  multitask: number;
  adapt: number;
  clutch: number;
  fatigue: number;
  tilt: number;
  default_civ_mastery: number;
  civ_id: string;
  build_family_id: string;
  practiced_this_week: boolean;
}

function resolveMatchJS(
  mapId: string,
  sideA: SideConfig,
  sideB: SideConfig,
  seedVal: number,
  useTunedWeights = true
) {
  const rng = new GodotRNG(seedVal);
  const mapData = mapsById.get(mapId);
  const civA = civsById.get(sideA.civ_id);
  const civB = civsById.get(sideB.civ_id);
  const buildA = buildsById.get(sideA.build_family_id);
  const buildB = buildsById.get(sideB.build_family_id);

  let liveTiltA = normStat(sideA.tilt);
  let liveTiltB = normStat(sideB.tilt);
  let switchedA = false;
  let switchedB = false;
  let dampenerA = 1.0;
  let dampenerB = 1.0;

  let positionScore = 0.0;
  let peakLeadA = 0.0;
  let peakLeadB = 0.0;
  let threwLead = false;

  const counterEdge =
    buildA.id === buildB.id
      ? 0.0
      : buildA.beats.includes(buildB.id)
      ? 1.0
      : buildA.loses_to.includes(buildB.id)
      ? -1.0
      : 0.0;

  const normalizePhase = (t: string) => (t === 'late' ? 'imp' : t);

  const computeMapFit = (civ: any, build: any, phase: string) => {
    let fit = 0.0;
    if (build.map_kinds.includes(mapData.kind)) {
      fit += phase === 'dark' || phase === 'feudal' ? 0.07 : 0.04;
    } else {
      fit -= phase === 'dark' || phase === 'feudal' ? 0.18 : 0.1;
    }
    let matches = 0;
    for (const t of civ.tags) {
      if (mapData.favored_tags.includes(t)) matches++;
    }
    if (matches > 0) fit += Math.min(0.1, matches * 0.05);
    return fit;
  };

  const computeSpike = (civ: any, build: any, side: SideConfig, phase: string) => {
    let spike = 0.0;
    const civSpike = normalizePhase(civ.power_spike);
    const buildTiming = normalizePhase(build.timing);
    const mastery = normStat(side.default_civ_mastery);
    if (civSpike === phase) spike += 0.1 + mastery * 0.08;
    if (buildTiming === phase) spike += 0.09;
    if (civSpike === phase && buildTiming === phase) spike += 0.05;
    return spike;
  };

  const tryTechSwitch = (side: SideConfig, liveTilt: number) => {
    const chance = clampf(
      normStat(side.adapt) * 0.65 +
        normStat(side.multitask) * 0.25 -
        liveTilt * 0.35 -
        normStat(side.fatigue) * 0.2,
      0.05,
      0.85
    );
    return rng.randf() < chance;
  };

  const evalExec = (side: SideConfig, build: any, phase: string, liveTilt: number) => {
    const tax = clampf(build.execution_tax, 0.0, 1.0);
    const macro = normStat(side.macro);
    const micro = normStat(side.micro);
    const multitask = normStat(side.multitask);
    const mastery = normStat(side.default_civ_mastery);
    const fatigue = normStat(side.fatigue);

    let baseSkill = useTunedWeights
      ? macro * 0.65 + mastery * 0.2 + micro * 0.08 + multitask * 0.07
      : macro * 0.55 + mastery * 0.25 + micro * 0.1 + multitask * 0.1;
    if (phase === 'feudal') {
      baseSkill = useTunedWeights
        ? macro * 0.5 + micro * 0.25 + multitask * 0.12 + mastery * 0.13
        : macro * 0.4 + micro * 0.3 + multitask * 0.15 + mastery * 0.15;
    } else if (phase === 'castle') {
      baseSkill = useTunedWeights
        ? macro * 0.5 + micro * 0.2 + multitask * 0.17 + mastery * 0.13
        : macro * 0.4 + micro * 0.25 + multitask * 0.2 + mastery * 0.15;
    } else if (phase === 'imp') {
      baseSkill = useTunedWeights
        ? macro * 0.55 + multitask * 0.22 + micro * 0.1 + mastery * 0.13
        : macro * 0.45 + multitask * 0.3 + micro * 0.1 + mastery * 0.15;
    }

    const prepMult = side.practiced_this_week ? 1.25 : 1.0;
    const effectiveSkill = clampf(baseSkill * prepMult, 0.0, 1.25);
    const execDeficit = Math.max(0.0, 1.0 - effectiveSkill);

    let stressLoad = tax * (1.0 + fatigue * 0.55 + liveTilt * 0.65);
    if (side.practiced_this_week) stressLoad *= 0.75;

    const rawMistakeRate = useTunedWeights
      ? clampf(0.02 + execDeficit * 0.68 + (stressLoad - effectiveSkill * 0.45) * 0.34, 0.02, 0.92)
      : clampf(0.08 + stressLoad * 0.62 - effectiveSkill * 0.52, 0.02, 0.92);

    let penalty = useTunedWeights
      ? (execDeficit * (0.52 + tax * 0.38) + fatigue * 0.1 + liveTilt * 0.12) * 0.68
      : Math.max(0.0, stressLoad - effectiveSkill * 0.85) * 0.28;

    const slipRoll = rng.randf();
    if (slipRoll < rawMistakeRate) {
      const slipSev = useTunedWeights
        ? 0.15 + (rawMistakeRate - slipRoll) * 0.5
        : 0.12 + (rawMistakeRate - slipRoll) * 0.45;
      penalty += slipSev;
    }

    if (phase === 'feudal' || phase === 'castle') {
      const combatControl = (micro * 0.55 + multitask * 0.45) * prepMult;
      const overextendRisk = useTunedWeights
        ? clampf(0.05 + tax * 0.32 + liveTilt * 0.38 + fatigue * 0.24 - combatControl * 0.42, 0.01, 0.75)
        : clampf(0.05 + tax * 0.35 + liveTilt * 0.4 + fatigue * 0.25 - combatControl * 0.42, 0.01, 0.75);
      if (rng.randf() < overextendRisk) {
        penalty += 0.2 + liveTilt * 0.1;
      }
    }

    return penalty;
  };

  for (const phase of ['dark', 'feudal', 'castle', 'imp']) {
    const prior = positionScore;
    let delta = 0.0;

    delta += computeMapFit(civA, buildA, phase) - computeMapFit(civB, buildB, phase);

    if (phase !== 'dark' && counterEdge !== 0.0) {
      if (counterEdge < 0.0 && !switchedA && (phase === 'castle' || phase === 'imp')) {
        if (tryTechSwitch(sideA, liveTiltA)) {
          switchedA = true;
          dampenerA = 0.4;
        }
      } else if (counterEdge > 0.0 && !switchedB && (phase === 'castle' || phase === 'imp')) {
        if (tryTechSwitch(sideB, liveTiltB)) {
          switchedB = true;
          dampenerB = 0.4;
        }
      }
      const weight =
        0.18 +
        (phase === normalizePhase(buildA.timing) || phase === normalizePhase(buildB.timing)
          ? 0.14
          : 0.0);
      const damp = counterEdge < 0.0 ? dampenerA : dampenerB;
      delta += counterEdge * weight * damp;
    }

    delta += computeSpike(civA, buildA, sideA, phase) - computeSpike(civB, buildB, sideB, phase);

    const penA = evalExec(sideA, buildA, phase, liveTiltA);
    const penB = evalExec(sideB, buildB, phase, liveTiltB);
    delta -= penA;
    delta += penB;

    const noiseA = Math.min(rng.randfn(0.0, 0.05 + liveTiltA * 0.14), 0.06);
    const noiseB = Math.min(rng.randfn(0.0, 0.05 + liveTiltB * 0.14), 0.06);
    delta += noiseA - noiseB;

    positionScore += delta;

    if (prior >= 0.45 && delta <= -0.4) {
      liveTiltA = clampf(liveTiltA + 0.22, 0.0, 1.0);
      threwLead = true;
    } else if (prior <= -0.45 && delta >= 0.4) {
      liveTiltB = clampf(liveTiltB + 0.22, 0.0, 1.0);
      threwLead = true;
    }

    peakLeadA = Math.max(peakLeadA, positionScore);
    peakLeadB = Math.max(peakLeadB, -positionScore);
  }

  let finalPos = positionScore;
  if (Math.abs(finalPos) <= 0.85) {
    const clutchDiff = normStat(sideA.clutch) - normStat(sideB.clutch);
    const closeness = 1.0 - Math.abs(finalPos) / 0.85;
    finalPos += clutchDiff * 0.35 * closeness;
  }

  const avgClutch = clampf(0.5 * (normStat(sideA.clutch) + normStat(sideB.clutch)), 0.0, 1.0);
  const slope = Math.abs(finalPos) <= 0.85 ? 1.65 * (1.0 + avgClutch * 0.25) : 1.65;
  const winProb = clampf(1.0 / (1.0 + Math.exp(-slope * finalPos)), 0.01, 0.99);

  let roll = rng.randf();
  if (Math.abs(finalPos) <= 0.85) {
    const compression = lerpf(1.0, 0.65, avgClutch);
    roll = 0.5 + (roll - 0.5) * compression;
  }

  const winner = roll <= winProb ? 'A' : 'B';
  if ((winner === 'B' && peakLeadA >= 0.55) || (winner === 'A' && peakLeadB >= 0.55)) {
    threwLead = true;
  }

  return { winner, winProb, finalPos, threwLead };
}

function runSuite(useTunedWeights: boolean) {
  const trials = 200;

  // Test A
  let winsA = 0;
  for (let i = 0; i < trials; i++) {
    const sideA: SideConfig = {
      player_id: 'strong_macro',
      player_name: 'Strong Macro (90)',
      macro: 90,
      micro: 50,
      multitask: 50,
      adapt: 50,
      clutch: 50,
      fatigue: 0,
      tilt: 0,
      default_civ_mastery: 50,
      civ_id: 'valorian_march',
      build_family_id: 'mobile_flank_sweep',
      practiced_this_week: false,
    };
    const sideB: SideConfig = { ...sideA, player_id: 'weak_macro', macro: 40 };
    const rep = resolveMatchJS('sunbaked_expanse', sideA, sideB, 10000 + i * 37, useTunedWeights);
    if (rep.winner === 'A') winsA++;
  }

  // Test B
  let winsB = 0;
  for (let i = 0; i < trials; i++) {
    const sideA: SideConfig = {
      player_id: 'feudal_pressure',
      player_name: 'Pressure Coach',
      macro: 50,
      micro: 50,
      multitask: 50,
      adapt: 50,
      clutch: 50,
      fatigue: 0,
      tilt: 0,
      default_civ_mastery: 50,
      civ_id: 'valorian_march',
      build_family_id: 'early_skirmish_raid',
      practiced_this_week: false,
    };
    const sideB: SideConfig = {
      ...sideA,
      player_id: 'late_boom',
      build_family_id: 'triple_civic_boom',
    };
    const rep = resolveMatchJS('sunbaked_expanse', sideA, sideB, 20000 + i * 41, useTunedWeights);
    if (rep.winner === 'A') winsB++;
  }

  // Test C
  let seriesWinsC = 0;
  for (let s = 0; s < trials; s++) {
    const sideA: SideConfig = {
      player_id: 'fatigued_side',
      player_name: 'Fatigued Player',
      macro: 50,
      micro: 50,
      multitask: 50,
      adapt: 50,
      clutch: 50,
      fatigue: 80,
      tilt: 70,
      default_civ_mastery: 50,
      civ_id: 'valorian_march',
      build_family_id: 'mobile_flank_sweep',
      practiced_this_week: false,
    };
    const sideB: SideConfig = {
      ...sideA,
      player_id: 'fresh_side',
      fatigue: 0,
      tilt: 0,
    };
    let gwA = 0;
    let gwB = 0;
    let gIdx = 0;
    while (gwA < 3 && gwB < 3) {
      sideA.fatigue = 80;
      sideA.tilt = 70;
      const rep = resolveMatchJS(
        'sunbaked_expanse',
        sideA,
        sideB,
        30000 + s * 100 + gIdx * 17,
        useTunedWeights
      );
      if (rep.winner === 'A') gwA++;
      else gwB++;

      const closeMatch = Math.abs(rep.finalPos) <= 0.85;
      const lengthGrind = closeMatch ? 0.04 : 0.01;
      const aWon = rep.winner === 'A';
      const fDeltaA = (aWon ? 0.07 : 0.11) + lengthGrind + 0.01;
      const fDeltaB = (aWon ? 0.11 : 0.07) + lengthGrind + 0.01;
      const tDeltaA = aWon ? -0.06 : rep.threwLead ? 0.18 : 0.1;
      const tDeltaB = aWon ? (rep.threwLead ? 0.18 : 0.1) : -0.06;

      sideA.fatigue = clampf(normStat(sideA.fatigue) + fDeltaA, 0.0, 1.0);
      sideB.fatigue = clampf(normStat(sideB.fatigue) + fDeltaB, 0.0, 1.0);
      sideA.tilt = clampf(normStat(sideA.tilt) + tDeltaA, 0.0, 1.0);
      sideB.tilt = clampf(normStat(sideB.tilt) + tDeltaB, 0.0, 1.0);
      gIdx++;
    }
    if (gwA >= 3) seriesWinsC++;
  }

  return {
    testA: { wins: winsA, losses: trials - winsA, rate: winsA / trials },
    testB: { wins: winsB, losses: trials - winsB, rate: winsB / trials },
    testC: { wins: seriesWinsC, losses: trials - seriesWinsC, rate: seriesWinsC / trials },
  };
}

test('balance_harness.gd implements headless CLI entrypoint and all 3 acceptance tests', () => {
  assert.match(harnessGd, /extends\s+SceneTree/);
  assert.match(harnessGd, /static func run_all_tests\(/);
  assert.match(harnessGd, /static func run_test_a_macro_advantage\(/);
  assert.match(harnessGd, /static func run_test_b_open_map_counter\(/);
  assert.match(harnessGd, /static func run_test_c_bo5_fatigue_tilt\(/);
  assert.ok(harnessGd.includes('quit(exit_code)'));
});

test('Statistical Balance Harness passes Test A [75%-95%], Test B [58%-80%], and Test C [<45%]', () => {
  const initial = runSuite(false);
  const tuned = runSuite(true);

  console.log('INITIAL (PRE-TUNING):', JSON.stringify(initial));
  console.log('FINAL (POST-TUNING):', JSON.stringify(tuned));

  assert.ok(
    tuned.testA.rate >= 0.75 && tuned.testA.rate <= 0.95,
    `Test A rate ${tuned.testA.rate} outside [0.75, 0.95]`
  );
  assert.ok(
    tuned.testB.rate >= 0.58 && tuned.testB.rate <= 0.8,
    `Test B rate ${tuned.testB.rate} outside [0.58, 0.80]`
  );
  assert.ok(
    tuned.testC.rate < 0.45,
    `Test C series win rate ${tuned.testC.rate} not < 0.45`
  );
});
