import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {run, sql} from './.generated/query.mjs';

// These stages are also used by record.mjs. Every result comes from a live
// SQLite database and the generated client; the recording contains no fixtures.
export function demo() {
  const directory = mkdtempSync(join(tmpdir(), 'eyg-sqlite-'));
  const path = join(directory, 'authorization.sqlite');
  const db = new DatabaseSync(path);
  return {
    path,
    source: () => readFileSync(new URL('./view.eyg', import.meta.url), 'utf8'),
    types: () => readFileSync(new URL('./.generated/query.d.mts', import.meta.url), 'utf8'),
    sql: () => sql.filter(s => s.includes('INSERT OR IGNORE') && s.includes('CROSS JOIN')).join(';\n\n'),
    setup() {
      db.exec(`
        CREATE TABLE grants(actor TEXT, resource TEXT, action TEXT) STRICT;
        CREATE TABLE children(parent TEXT, child TEXT) STRICT;
        INSERT INTO grants VALUES ('alice','atlas','read'), ('bob','billing','write');
        INSERT INTO children VALUES ('atlas','report'), ('report','appendix');
      `);
      return db.prepare('SELECT * FROM grants').all();
    },
    initial() {
      const rows = run(db);
      assert.deepEqual(rows.map(r => r.resource).sort(), ['appendix','atlas','report']);
      assert(rows.every(r => r.action === 'read'));
      return rows;
    },
    extend() {
      db.prepare('INSERT INTO children VALUES (?, ?)').run('atlas', 'dashboard');
      const rows = run(db);
      assert.deepEqual(rows.map(r => r.resource).sort(), ['appendix','atlas','dashboard','report']);
      return rows;
    },
    revoke() {
      db.prepare('DELETE FROM grants WHERE actor = ?').run('alice');
      const rows = run(db);
      assert.deepEqual(rows, []);
      assert.equal(db.prepare('SELECT count(*) AS n FROM grants').get().n, 1);
      assert.deepEqual(db.prepare('SELECT name FROM sqlite_temp_master').all(), []);
      return rows;
    },
    close() { db.close(); rmSync(directory, {recursive:true, force:true}); },
  };
}

if (process.argv[1] && import.meta.url === new URL(process.argv[1], 'file:').href) {
  const session = demo();
  try {
    console.log('SQLite file:', session.path);
    console.log('\nGenerated result type:\n' + session.types());
    console.log('Stored grants:', session.setup());
    console.log('Alice, including inherited access:', session.initial());
    console.log('After inserting a new child:', session.extend());
    console.log('After revoking Alice’s grant:', session.revoke());
    console.log('All assertions passed. The client inferred and decoded every result.');
  } finally { session.close(); }
}
