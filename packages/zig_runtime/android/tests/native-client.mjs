import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

/** Async Node transport to the stdlib ctypes proxy, not a simulated native VM. */
export class NativeClient {
  constructor(library) {
    this.nextId = 1;
    this.pending = new Map();
    let stderr = '';
    this.child = spawn(process.env.PYTHON ?? 'python3', [
      fileURLToPath(new URL('../scripts/native-proxy.py', import.meta.url)), library,
    ], { stdio: ['pipe', 'pipe', 'pipe'] });
    this.child.stderr.on('data', bytes => { stderr = (stderr + bytes).slice(-8192); });
    this.exit = new Promise((resolve, reject) => {
      this.child.once('error', reject);
      this.child.once('close', (code, signal) => {
        const error = new Error(`Native proxy exited (${signal ?? code}): ${stderr}`);
        for (const request of this.pending.values()) request.reject(error);
        this.pending.clear();
        if (code === 0) resolve(); else reject(error);
      });
    });
    this.exit.catch(() => {});
    createInterface({ input: this.child.stdout }).on('line', line => {
      const response = JSON.parse(line);
      const request = this.pending.get(response.id);
      if (!request) throw new Error('Unexpected native proxy response');
      this.pending.delete(response.id);
      if (response.ok) request.resolve(response.value); else request.reject(new Error(response.error));
    });
  }

  request(method, ...args) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.child.kill();
        reject(new Error(`Native proxy timeout at ${method}`));
      }, 10000);
      this.pending.set(id, {
        resolve: value => { clearTimeout(timer); resolve(value); },
        reject: error => { clearTimeout(timer); reject(error); },
      });
      this.child.stdin.write(JSON.stringify({ id, method, args }) + '\n', error => {
        if (error) this.pending.get(id)?.reject(error);
      });
    });
  }

  create() { return this.request('create'); }
  evaluate(id, source) { return this.request('evaluate', id, source); }
  resume(id, reply) { return this.request('resume', id, reply); }
  destroy(id) { return this.request('destroy', id); }
  stats() { return this.request('stats'); }
  async close() { this.child.stdin.end(); await this.exit; }
}
