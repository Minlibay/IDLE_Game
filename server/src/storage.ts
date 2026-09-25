// Хранилище на встроенном SQLite (node:sqlite). Зоны и игроки лежат JSON-строками —
// схема простая и легко меняется, пока прототип. Пишется сразу при каждом изменении.

import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import type { Zone } from "./world/generator.ts";
import type { Player, ReportData } from "./world/game.ts";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS zones (id INTEGER PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS players (id INTEGER PRIMARY KEY, token TEXT UNIQUE NOT NULL, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  data TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS reports_by_player ON reports (player_id, id);
`;

export type StoredReport = { id: number; createdAt: number; data: ReportData };

export class Storage {
  private db: DatabaseSync;

  constructor(path: string) {
    if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
    this.db = new DatabaseSync(path);
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.db.exec(SCHEMA);
  }

  close(): void {
    this.db.close();
  }

  getMeta(key: string): string | undefined {
    const row = this.db.prepare("SELECT value FROM meta WHERE key = ?").get(key) as { value: string } | undefined;
    return row?.value;
  }

  setMeta(key: string, value: string): void {
    this.db.prepare("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
      .run(key, value);
  }

  loadZones(): Zone[] {
    const rows = this.db.prepare("SELECT data FROM zones ORDER BY id").all() as { data: string }[];
    return rows.map((row) => JSON.parse(row.data) as Zone);
  }

  saveZone(zone: Zone): void {
    this.db.prepare("INSERT INTO zones (id, data) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET data = excluded.data")
      .run(zone.id, JSON.stringify(zone));
  }

  clearZones(): void {
    this.db.exec("DELETE FROM zones");
  }

  saveZones(zones: Zone[]): void {
    this.transaction(() => {
      for (const zone of zones) this.saveZone(zone);
    });
  }

  loadPlayers(): Player[] {
    const rows = this.db.prepare("SELECT data FROM players ORDER BY id").all() as { data: string }[];
    return rows.map((row) => JSON.parse(row.data) as Player);
  }

  savePlayer(player: Player): void {
    this.db.prepare(
      "INSERT INTO players (id, token, data) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET token = excluded.token, data = excluded.data",
    ).run(player.id, player.token, JSON.stringify(player));
  }

  addReport(playerId: number, createdAt: number, data: ReportData, keep: number): void {
    this.db.prepare("INSERT INTO reports (player_id, created_at, data) VALUES (?, ?, ?)")
      .run(playerId, createdAt, JSON.stringify(data));
    this.db.prepare(
      `DELETE FROM reports WHERE player_id = ? AND id NOT IN
       (SELECT id FROM reports WHERE player_id = ? ORDER BY id DESC LIMIT ?)`,
    ).run(playerId, playerId, keep);
  }

  loadReports(playerId: number, limit: number): StoredReport[] {
    const rows = this.db.prepare(
      "SELECT id, created_at, data FROM reports WHERE player_id = ? ORDER BY id DESC LIMIT ?",
    ).all(playerId, limit) as { id: number; created_at: number; data: string }[];
    return rows.map((row) => ({ id: row.id, createdAt: row.created_at, data: JSON.parse(row.data) as ReportData }));
  }

  transaction(work: () => void): void {
    this.db.exec("BEGIN");
    try {
      work();
      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }
}
