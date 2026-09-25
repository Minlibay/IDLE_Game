// HTTP API (JSON). Авторизация: заголовок "Authorization: Bearer <token>".
// Вход пока через регистрацию по имени (dev); позже — Steam-тикеты.

import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { gzipSync } from "node:zlib";
import type { GameData } from "./gameData.ts";
import { sanitizeArmy } from "./world/army.ts";
import { GameError, type Game, type Player } from "./world/game.ts";
import { KingdomError } from "./world/kingdom.ts";

type Context = {
  url: URL;
  body: Record<string, unknown>;
  player: Player;
  now: number;
};

type Route = {
  auth: boolean;
  handle: (ctx: Context) => unknown;
};

export type HttpSettings = { maxBodyBytes: number; maxUnitsPerType: number; marchSeconds: number; castleMarchSeconds: number; gzipMinBytes: number };

export function createHttpServer(game: Game, gameData: GameData, settings: HttpSettings): Server {
  const units = (input: unknown) => {
    try {
      return sanitizeArmy(input, gameData.units, settings.maxUnitsPerType);
    } catch (error) {
      throw new GameError((error as Error).message);
    }
  };

  const routes: Record<string, Route> = {
    "GET /api/health": { auth: false, handle: () => ({ ok: true, version: game.worldVersion }) },

    "GET /api/config": {
      auth: false,
      handle: () => ({
        marchSeconds: settings.marchSeconds,
        castleMarchSeconds: settings.castleMarchSeconds,
        units: gameData.units,
      }),
    },

    "POST /api/auth/register": {
      auth: false,
      handle: ({ body, now }) => {
        const player = game.register(String(body.name ?? ""), now);
        return { token: player.token, me: game.playerView(player, now) };
      },
    },

    "GET /api/world": {
      auth: true,
      handle: ({ url, now }) => game.worldView(Number(url.searchParams.get("since") ?? 0) || 0, now),
    },

    "GET /api/me": { auth: true, handle: ({ player, now }) => game.playerView(player, now) },

    "POST /api/hero": {
      auth: true,
      handle: ({ player, body, now }) => {
        game.setHeroLevel(player, body.level, now);
        return game.playerView(player, now);
      },
    },

    "POST /api/army/deploy": {
      auth: true,
      handle: ({ player, body, now }) => {
        game.deploy(player, units(body.units), now);
        return game.playerView(player, now);
      },
    },

    "POST /api/army/recall": {
      auth: true,
      handle: ({ player, body, now }) => {
        const returned = game.recall(player, units(body.units), now);
        return { returned, me: game.playerView(player, now) };
      },
    },

    "POST /api/move": {
      auth: true,
      handle: ({ player, body, now }) => {
        game.move(player, body.zoneId, now);
        return game.playerView(player, now);
      },
    },

    "POST /api/garrison": {
      auth: true,
      handle: ({ player, body, now }) => {
        game.garrison(player, units(body.units), now);
        return game.playerView(player, now);
      },
    },

    "POST /api/garrison/withdraw": {
      auth: true,
      handle: ({ player, body, now }) => {
        game.withdraw(player, units(body.units), now);
        return game.playerView(player, now);
      },
    },

    "POST /api/kingdom/build": {
      auth: true,
      handle: ({ player, body, now }) => {
        game.build(player, body.building, now);
        return game.playerView(player, now);
      },
    },

    "POST /api/kingdom/recruit": {
      auth: true,
      handle: ({ player, body, now }) => {
        game.recruit(player, body.unit, body.count, now);
        return game.playerView(player, now);
      },
    },

    "POST /api/kingdom/cancel": {
      auth: true,
      handle: ({ player, body, now }) => {
        game.cancelTraining(player, body.index, now);
        return game.playerView(player, now);
      },
    },

    "POST /api/kingdom/consume": {
      auth: true,
      handle: ({ player, body, now }) => {
        const taken = game.consume(player, body.resources, now);
        return { taken, me: game.playerView(player, now) };
      },
    },

    "POST /api/kingdom/deposit": {
      auth: true,
      handle: ({ player, body, now }) => {
        const accepted = game.deposit(player, body.gold, now);
        return { accepted, me: game.playerView(player, now) };
      },
    },
  };

  return createServer(async (req, res) => {
    try {
      const url = new URL(req.url ?? "/", "http://localhost");
      const route = routes[`${req.method} ${url.pathname}`];
      const reply = (status: number, payload: unknown) => send(req, res, status, payload, settings.gzipMinBytes);
      if (!route) return reply(404, { error: "Not found" });

      const body = req.method === "POST" ? await readJson(req, settings.maxBodyBytes) : {};
      let player: Player | undefined;
      if (route.auth) {
        const token = (req.headers.authorization ?? "").replace(/^Bearer\s+/i, "");
        player = token ? game.getPlayerByToken(token) : undefined;
        if (!player) return reply(401, { error: "Нужно войти заново" });
      }
      const result = route.handle({ url, body, player: player as Player, now: Date.now() });
      reply(200, result);
    } catch (error) {
      const reply = (status: number, payload: unknown) => send(req, res, status, payload, settings.gzipMinBytes);
      if (error instanceof GameError) return reply(error.status, { error: error.message });
      if (error instanceof KingdomError) return reply(400, { error: error.message });
      if (error instanceof SyntaxError) return reply(400, { error: "Некорректный JSON" });
      console.error(error);
      reply(500, { error: "Внутренняя ошибка сервера" });
    }
  });
}

/** JSON-ответ; крупные ответы сжимаются gzip, если клиент это поддерживает (Godot — да). */
function send(req: IncomingMessage, res: ServerResponse, status: number, payload: unknown, gzipMinBytes: number): void {
  const json = Buffer.from(JSON.stringify(payload), "utf8");
  const acceptsGzip = /\bgzip\b/.test(String(req.headers["accept-encoding"] ?? ""));
  const headers: Record<string, string | number> = { "Content-Type": "application/json; charset=utf-8" };
  let body = json;
  if (acceptsGzip && json.length >= gzipMinBytes) {
    body = gzipSync(json);
    headers["Content-Encoding"] = "gzip";
  }
  headers["Content-Length"] = body.length;
  res.writeHead(status, headers);
  res.end(body);
}

async function readJson(req: IncomingMessage, maxBytes: number): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > maxBytes) throw new GameError("Слишком большой запрос", 413);
    chunks.push(chunk as Buffer);
  }
  if (size === 0) return {};
  const parsed: unknown = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) throw new GameError("Ожидался JSON-объект");
  return parsed as Record<string, unknown>;
}
