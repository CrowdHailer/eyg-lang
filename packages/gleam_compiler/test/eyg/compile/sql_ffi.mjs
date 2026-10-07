import {spawnSync} from 'node:child_process';

export function run(client, setup, assertions) {
  const script = `
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
const {run, decode, sql} = await import('data:text/javascript;base64,' + ${JSON.stringify(Buffer.from(client).toString('base64'))});
const db = new DatabaseSync(':memory:');
db.exec(${JSON.stringify(setup)});
${assertions}
db.close();
console.log('passed');
`;
  const child = spawnSync('node', ['--input-type=module', '-'], {
    input: script, encoding: 'utf8', timeout: 10000, maxBuffer: 4 * 1024 * 1024,
  });
  return child.status === 0 ? child.stdout.trim() : `${child.error || ''}\n${child.stderr}\n${child.stdout}`.replaceAll(/data:text\/javascript;base64,[A-Za-z0-9+/=]+/g, 'generated-client.mjs');
}
