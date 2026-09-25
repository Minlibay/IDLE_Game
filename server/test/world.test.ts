import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { attackOf, defenseOf, sanitizeArmy } from "../src/world/army.ts";
import { resolveBattle } from "../src/world/battle.ts";
import { generateZones } from "../src/world/generator.ts";
import { hexDistance, neighbors, tierOf } from "../src/world/grid.ts";
import { gameData, settings } from "./helpers.ts";

const units = gameData.units;

describe("grid", () => {
  it("inner hex has 6 neighbours, all at distance 1", () => {
    const hex = { col: 10, row: 11 };
    const list = neighbors(hex, 50, 40);
    assert.equal(list.length, 6);
    for (const other of list) assert.equal(hexDistance(hex, other), 1);
  });

  it("corner hex has fewer neighbours", () => {
    assert.ok(neighbors({ col: 0, row: 0 }, 50, 40).length < 6);
  });

  it("tier is highest in the centre and 1 on the edges", () => {
    assert.equal(tierOf({ col: 25, row: 20 }, 50, 40, 10), 10);
    assert.equal(tierOf({ col: 0, row: 0 }, 50, 40, 10), 1);
  });
});

describe("generator", () => {
  const zones = generateZones(units, settings, 1);

  it("creates 2000 zones", () => {
    assert.equal(zones.length, 2000);
  });

  it("neutral armies get stronger towards the centre", () => {
    const power = (tier: number) => {
      const list = zones.filter((zone) => zone.tier === tier);
      return list.reduce((sum, zone) => sum + attackOf(zone.neutral, units) + defenseOf(zone.neutral, units), 0) / list.length;
    };
    assert.ok(power(10) > power(5) * 3, "tier 10 must be much stronger than tier 5");
    assert.ok(power(5) > power(1) * 3, "tier 5 must be much stronger than tier 1");
  });

  it("is deterministic for the same seed", () => {
    assert.deepEqual(generateZones(units, settings, 1)[500], zones[500]);
  });
});

describe("battle", () => {
  const battleSettings = { heroPowerPerLevel: 5, lossExponent: 1.5, luck: 0 };

  it("stronger attacker wins, defender loses everything", () => {
    const result = resolveBattle({ army: { knight: 10 }, heroLevel: 1 }, { army: { militia: 10 }, heroLevel: 0 }, units, battleSettings);
    assert.equal(result.attackerWins, true);
    assert.deepEqual(result.defenderArmy, {});
    assert.ok((result.attackerArmy.knight ?? 0) > 0 && (result.attackerArmy.knight ?? 0) < 10, "winner takes some losses");
  });

  it("weaker attacker loses the whole army", () => {
    const result = resolveBattle({ army: { militia: 5 }, heroLevel: 1 }, { army: { spearman: 20 }, heroLevel: 0 }, units, battleSettings);
    assert.equal(result.attackerWins, false);
    assert.deepEqual(result.attackerArmy, {});
    assert.equal(result.attackerLost.militia, 5);
  });

  it("hero alone can beat a tiny army", () => {
    const result = resolveBattle({ army: {}, heroLevel: 10 }, { army: { militia: 3 }, heroLevel: 0 }, units, battleSettings);
    assert.equal(result.attackerWins, true);
  });
});

describe("sanitizeArmy", () => {
  it("rejects unknown units and bad counts", () => {
    assert.throws(() => sanitizeArmy({ dragon: 1 }, units, 1000));
    assert.throws(() => sanitizeArmy({ militia: -1 }, units, 1000));
    assert.throws(() => sanitizeArmy({ militia: 1.5 }, units, 1000));
    assert.deepEqual(sanitizeArmy({ militia: 3, knight: 0 }, units, 1000), { militia: 3 });
  });
});
