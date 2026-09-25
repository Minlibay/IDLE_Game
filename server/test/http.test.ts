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

    const deploy = await call("POST", "/api/army/deploy", { units: { militia: 3 } }, token);
    assert.equal(deploy.status, 200);
    assert.deepEqual(deploy.json.army, { militia: 3 });

    const world = await call("GET", "/api/world?since=0", undefined, token);
    assert.equal(world.json.zones.length, 2000);
    assert.ok(world.json.players.some((player: { name: string }) => player.name === "Http"));
  });

  it("rejects missing token and bad input", async () => {
    assert.equal((await call("GET", "/api/me")).status, 401);
    const reg = await call("POST", "/api/auth/register", { name: "Bad" });
    const bad = await call("POST", "/api/army/deploy", { units: { dragon: 5 } }, reg.json.token);
    assert.equal(bad.status, 400);
    assert.match(bad.json.error, /unknown unit/);
  });
});
