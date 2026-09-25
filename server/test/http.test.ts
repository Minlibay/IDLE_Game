import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { after, before, describe, it } from "node:test";
import { createHttpServer } from "../src/http.ts";
import { createGame, gameData, settings } from "./helpers.ts";

describe("http api", () => {
  const { game } = createGame();
  const server = createHttpServer(game, gameData, settings);
  let base = "";

  before(async () => {
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });
  after(() => server.close());

  async function call(method: string, path: string, body?: unknown, token?: string) {
    const response = await fetch(base + path, {
      method,
      headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: response.status, json: (await response.json()) as Record<string, any> };
  }

  it("register → me → deploy → world", async () => {
    const reg = await call("POST", "/api/auth/register", { name: "Http" });
    assert.equal(reg.status, 200);
    const token = reg.json.token as string;

    const me = await call("GET", "/api/me", undefined, token);
    assert.equal(me.status, 200);
    assert.equal(me.json.name, "Http");

    assert.equal((await call("POST", "/api/army/deploy", { units: { militia: 3 } }, token)).status, 400, "no soldiers in the castle yet");
    game.getPlayerByToken(token)!.kingdom.army = { militia: 3 };
    const deploy = await call("POST", "/api/army/deploy", { units: { militia: 3 } }, token);
    assert.equal(deploy.status, 200);
    assert.deepEqual(deploy.json.army, { militia: 3 });

    const world = await call("GET", "/api/world?since=0", undefined, token);
    assert.equal(world.json.zones.length, settings.gridCols * settings.gridRows);
    assert.ok(world.json.players.some((player: { name: string }) => player.name === "Http"));
  });

  it("large responses are gzip-compressed", async () => {
    const reg = await call("POST", "/api/auth/register", { name: "Gzip" });
    const response = await fetch(base + "/api/world?since=0", {
      headers: { Authorization: `Bearer ${reg.json.token}`, "Accept-Encoding": "gzip" },
    });
    assert.equal(response.headers.get("content-encoding"), "gzip");
    const body = (await response.json()) as { zones: unknown[] };
    assert.equal(body.zones.length, settings.gridCols * settings.gridRows);
  });

  it("rejects missing token and bad input", async () => {
    assert.equal((await call("GET", "/api/me")).status, 401);
    const reg = await call("POST", "/api/auth/register", { name: "Bad" });
    const bad = await call("POST", "/api/army/deploy", { units: { dragon: 5 } }, reg.json.token);
    assert.equal(bad.status, 400);
    assert.match(bad.json.error, /unknown unit/);
  });

  it("castle actions go through the server", async () => {
    const reg = await call("POST", "/api/auth/register", { name: "Builder" });
    const token = reg.json.token as string;
    assert.equal(reg.json.me.kingdom.levels.town_hall, 1);

    const built = await call("POST", "/api/kingdom/build", { building: "farm" }, token);
    assert.equal(built.status, 200);
    assert.equal(built.json.kingdom.construction.id, "farm");

    const busy = await call("POST", "/api/kingdom/build", { building: "well" }, token);
    assert.equal(busy.status, 400);
    assert.match(busy.json.error, /заняты/);

    const noBarracks = await call("POST", "/api/kingdom/recruit", { unit: "militia", count: 1 }, token);
    assert.equal(noBarracks.status, 400);

    const eaten = await call("POST", "/api/kingdom/consume", { resources: { food: 2 } }, token);
    assert.equal(eaten.status, 200);
    assert.equal(eaten.json.taken.food, 2);

    const deposit = await call("POST", "/api/kingdom/deposit", { gold: 50 }, token);
    assert.equal(deposit.status, 400, "allowance is empty right after registration");

    const gear = await call("POST", "/api/hero", { level: 3, armyGear: { ARMY_POWER: 12.5 } }, token);
    assert.equal(gear.status, 200);
    assert.equal(gear.json.heroLevel, 3);
    assert.deepEqual(gear.json.armyGear, { ARMY_POWER: 12.5 });
    const badGear = await call("POST", "/api/hero", { armyGear: { NOPE: 1 } }, token);
    assert.equal(badGear.status, 400);
  });
});
