import fs from "node:fs";
import { Result$Ok, Result$Error } from "../gleam.mjs";

export function readStdin() {
  try {
    return Result$Ok(fs.readFileSync(0, "utf8"));
  } catch (error) {
    return Result$Error(`failed to read stdin: ${error.message}`);
  }
}

import { toList, BitArray$BitArray } from "../gleam.mjs";
import {
  SqlValue$SqlInteger,
  SqlValue$SqlText,
  SqlValue$SqlBlob,
  SqlValue$SqlNull,
  SqlValue$isSqlInteger,
  SqlValue$isSqlText,
  SqlValue$isSqlBlob,
  SqlValue$SqlInteger$0,
  SqlValue$SqlText$0,
  SqlValue$SqlBlob$0,
  SqlResult$SqlResult,
} from "./system.mjs";

// One connection per file for the life of the process, so temporary tables and
// transactions span statements. Bun ships SQLite, Node 22.5+ has node:sqlite.
const connections = new Map();

function open(path) {
  if (connections.has(path)) return connections.get(path);
  let db;
  if (globalThis.Bun) {
    const { Database } = import.meta.require("bun:sqlite");
    const raw = new Database(path, { create: true, strict: true });
    db = {
      run: (sql, params) => {
        const statement = raw.prepare(sql);
        if (statement.columnNames.length === 0) {
          const { changes } = statement.run(...params);
          return { columns: [], rows: [], changes };
        }
        return { columns: statement.columnNames, rows: statement.values(...params), changes: 0 };
      },
    };
  } else {
    const { DatabaseSync } = process.getBuiltinModule("node:sqlite");
    const raw = new DatabaseSync(path);
    db = {
      run: (sql, params) => {
        const statement = raw.prepare(sql);
        const columns = statement.columns().map((c) => c.name);
        if (columns.length === 0) {
          const { changes } = statement.run(...params);
          return { columns, rows: [], changes: Number(changes) };
        }
        statement.setReturnArrays?.(true);
        const rows = statement.all(...params).map((row) => Array.isArray(row) ? row : columns.map((c) => row[c]));
        return { columns, rows, changes: 0 };
      },
    };
  }
  connections.set(path, db);
  return db;
}

function toSql(value) {
  if (SqlValue$isSqlInteger(value)) return SqlValue$SqlInteger$0(value);
  if (SqlValue$isSqlText(value)) return SqlValue$SqlText$0(value);
  if (SqlValue$isSqlBlob(value)) {
    const bits = SqlValue$SqlBlob$0(value);
    return bits.rawBuffer.slice(0, bits.byteSize);
  }
  return null;
}

function fromSql(value) {
  if (value === null || value === undefined) return SqlValue$SqlNull();
  if (typeof value === "bigint") return SqlValue$SqlInteger(Number(value));
  if (typeof value === "number") {
    if (!Number.isInteger(value)) throw new Error(`EYG has no floats, SQLite returned ${value}`);
    return SqlValue$SqlInteger(value);
  }
  if (typeof value === "string") return SqlValue$SqlText(value);
  if (value instanceof Uint8Array) return SqlValue$SqlBlob(BitArray$BitArray(new Uint8Array(value)));
  throw new Error(`unsupported SQLite value ${value}`);
}

export function runSql(path, sql, params) {
  try {
    const db = open(path);
    const result = db.run(sql, params.toArray().map(toSql));
    return Result$Ok(
      SqlResult$SqlResult(
        toList(result.columns),
        toList(result.rows.map((row) => toList(row.map(fromSql)))),
        result.changes,
      ),
    );
  } catch (error) {
    return Result$Error(error.message);
  }
}
