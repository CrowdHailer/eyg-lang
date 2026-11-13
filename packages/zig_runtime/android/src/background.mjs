import { fromSpec, toSpec } from './effects.mjs';
import { runSession } from './session.mjs';

const STATE_KEY = '@eyg/background/v1/tasks';
const RESULT_PREFIX = '@eyg/background/v1/result/';
const MAX_TASKS = 16;
const MAX_SOURCE = 64 * 1024;
const MAX_RESULT = 64 * 1024;
const slotName = slot => `eyg-background:${slot}`;
const resultKey = name => RESULT_PREFIX + encodeURIComponent(name);

function bytes(text) {
  let length = 0;
  for (const char of text) {
    const point = char.codePointAt(0);
    length += point < 128 ? 1 : point < 2048 ? 2 : point < 65536 ? 3 : 4;
  }
  return length;
}

function jsonData(value, limit) {
  const text = JSON.stringify(value, (_, item) => {
    if (typeof item === 'function' || typeof item === 'symbol' || typeof item === 'bigint' ||
        typeof item === 'number' && !Number.isFinite(item)) throw new Error('Background data must be finite JSON data');
    return item;
  });
  if (text === undefined || bytes(text) > limit) throw new Error('Background data exceeds storage limit');
  return JSON.parse(text);
}

function taskName(name) {
  if (typeof name !== 'string' || !name.trim() || bytes(name) > 128) throw new Error('Invalid background task name');
  return name;
}

function definition(settings, slot) {
  const name = taskName(settings?.name);
  if (typeof settings.source !== 'string' || !settings.source.trim() || bytes(settings.source) > MAX_SOURCE) throw new Error('Background source must contain 1–65536 UTF-8 bytes');
  const timeout_ms = settings.timeout_ms ?? 30000;
  if (!Number.isSafeInteger(timeout_ms) || timeout_ms < 1 || timeout_ms > 300000) throw new Error('Invalid background timeout');
  const result_kind = settings.result_kind ?? 'task';
  if (!['task', 'fetch', 'value'].includes(result_kind)) throw new Error('Invalid background result kind');
  if (settings.directory != null && (typeof settings.directory !== 'string' || bytes(settings.directory) > 4096)) throw new Error('Invalid background directory');
  return { name, source: settings.source, slot, timeout_ms, result_kind,
    metadata: jsonData(settings.metadata ?? null, 16 * 1024),
    ...(settings.directory == null ? {} : { directory: settings.directory }) };
}

function describe(task) {
  const { slot, ...fields } = task;
  return { ...fields, task_name: slotName(slot) };
}

function callbackResult(kind, record) {
  const succeeded = record.status === 'done';
  if (kind === 'value') return succeeded ? record.value : null;
  if (kind === 'fetch') return succeeded ? 2 : 3;
  return succeeded ? 1 : 2;
}

/** Persist entrypoints, not live continuations. Every event gets a fresh VM. */
export class BackgroundTasks {
  constructor({ storage, taskManager, native, hostFactory, directory = '.', nativeOptions = {}, now = Date.now }) {
    this.storage = storage;
    this.taskManager = taskManager;
    this.native = native;
    this.hostFactory = hostFactory;
    this.directory = directory;
    this.nativeOptions = nativeOptions;
    this.now = now;
    this.tasks = new Map();
    this.identities = new Map();
    this.active = new Map();
    this.retiring = new Set();
    this.serial = Promise.resolve();
    this.closed = false;
    this.resetting = false;
    this.nextRun = 1;
    // Expo requires synchronous global defineTask calls. Durable names select
    // fixed slots after AsyncStorage hydration, including in a headless launch.
    for (let slot = 0; slot < MAX_TASKS; slot++) {
      taskManager.defineTask(slotName(slot), async body => {
        let task;
        try {
          await this.ready;
          task = [...this.tasks.values()].find(task => task.slot === slot);
          if (!task) return 2;
          const result = await this.execute(task.name, body);
          return callbackResult(task.result_kind, result);
        } catch {
          return callbackResult(task?.result_kind ?? 'task', { status: 'error' });
        }
      });
    }
    this.ready = this.restore();
    this.ready.catch(() => {});
  }

  async restore() {
    const text = await this.storage.getItem(STATE_KEY);
    if (text == null) return;
    if (bytes(text) > 2 * 1024 * 1024) throw new Error('Background task store exceeds limit');
    const saved = JSON.parse(text);
    if (saved.version !== 1 || !Array.isArray(saved.tasks) || saved.tasks.length > MAX_TASKS) throw new Error('Invalid background task store');
    const slots = new Set();
    const tasks = new Map();
    const identities = new Map();
    const savedIdentities = saved.identities ?? saved.tasks.map(({ name, slot }) => ({ name, slot }));
    if (!Array.isArray(savedIdentities) || savedIdentities.length > MAX_TASKS) throw new Error('Invalid background identities');
    for (const entry of savedIdentities) {
      const name = taskName(entry.name);
      if (!Number.isSafeInteger(entry.slot) || entry.slot < 0 || entry.slot >= MAX_TASKS || slots.has(entry.slot) || identities.has(name)) throw new Error('Invalid background identity slot');
      slots.add(entry.slot);
      identities.set(name, entry.slot);
    }
    slots.clear();
    for (const entry of saved.tasks) {
      if (!Number.isSafeInteger(entry.slot) || entry.slot < 0 || entry.slot >= MAX_TASKS || slots.has(entry.slot)) throw new Error('Invalid background slot');
      const task = definition(entry, entry.slot);
      if (tasks.has(task.name)) throw new Error('Duplicate background task name');
      if (identities.get(task.name) !== task.slot) throw new Error('Background task identity does not match its slot');
      slots.add(task.slot);
      tasks.set(task.name, task);
    }
    this.tasks = tasks;
    this.identities = identities;
  }

  edit(operation) {
    const result = this.serial.then(operation);
    this.serial = result.catch(() => {});
    return result;
  }

  async available() {
    await this.ready;
    this.checkOpen();
  }

  checkOpen() {
    if (this.closed) throw new Error('Background adapter is closed');
    if (this.resetting) throw new Error('Background slot reset is in progress');
  }

  async save(tasks, identities = this.identities) {
    await this.storage.setItem(STATE_KEY, JSON.stringify({ version: 1, tasks: [...tasks.values()],
      identities: [...identities].map(([name, slot]) => ({ name, slot })) }));
  }

  async define(settings) {
    await this.available();
    return this.edit(async () => {
      this.checkOpen();
      const name = taskName(settings?.name);
      if (this.retiring.has(name)) throw new Error('Background task is being unregistered');
      const old = this.tasks.get(name);
      const slots = new Set(this.identities.values());
      const slot = this.identities.get(name) ?? Array.from({ length: MAX_TASKS }, (_, i) => i).find(slot => !slots.has(slot));
      if (slot === undefined) throw new Error('Background identity limit is 16; forget tasks and reset slots before adding new names');
      const task = definition(settings, slot);
      const tasks = new Map(this.tasks).set(name, task);
      const identities = new Map(this.identities).set(name, slot);
      await this.save(tasks, identities);
      if (old) {
        this.abort(old.slot, 'replaced');
        this.active.delete(old.slot);
      }
      this.tasks = tasks;
      this.identities = identities;
      return describe(task);
    });
  }

  async list() {
    await this.available();
    return this.edit(() => [...this.tasks.values()].map(describe));
  }

  async get(name) {
    await this.available();
    return this.edit(() => {
      const task = this.tasks.get(taskName(name));
      return task ? describe(task) : null;
    });
  }

  async result(name) {
    await this.available();
    return this.edit(async () => {
      const text = await this.storage.getItem(resultKey(taskName(name)));
      return text == null ? null : JSON.parse(text);
    });
  }

  abort(slot, reason) {
    const run = this.active.get(slot);
    if (!run) return false;
    run.reason = reason;
    run.controller.abort();
    return true;
  }

  async cancel(name) {
    await this.available();
    return this.edit(() => {
      const task = this.tasks.get(taskName(name));
      return task ? this.abort(task.slot, 'cancelled') : false;
    });
  }

  async forget(name) {
    await this.available();
    const task = await this.edit(() => {
      this.checkOpen();
      const task = this.tasks.get(taskName(name));
      if (!task) return null;
      if (this.retiring.has(name)) throw new Error('Background task is being unregistered');
      this.retiring.add(name);
      this.abort(task.slot, 'unregistered');
      return task;
    });
    if (!task) return false;
    try {
      // Do not hold the storage queue while OS unregistration waits. An active
      // callback must be able to finish and acknowledge its cancellation first.
      if (!this.taskManager.isTaskRegisteredAsync || await this.taskManager.isTaskRegisteredAsync(slotName(task.slot))) {
        await this.taskManager.unregisterTaskAsync(slotName(task.slot));
      }
      return await this.edit(async () => {
        const tasks = new Map(this.tasks);
        tasks.delete(name);
        await this.save(tasks);
        this.tasks = tasks;
        this.active.delete(task.slot);
        await this.storage.removeItem(resultKey(name));
        return true;
      });
    } finally {
      await this.edit(() => this.retiring.delete(name));
    }
  }

  /** @param {string} name @param {unknown} data */
  async run(name, data = null) {
    return this.execute(name, { data, error: null, executionInfo: { eventId: 'manual', taskName: name } });
  }

  async resetSlots() {
    await this.available();
    await this.edit(() => {
      this.checkOpen();
      if (this.tasks.size || this.active.size || this.retiring.size) throw new Error('Forget every background task before resetting slots');
      this.resetting = true;
    });
    try {
      if (!this.taskManager.getRegisteredTasksAsync) throw new Error('Cannot verify OS background registrations');
      const registered = await this.taskManager.getRegisteredTasksAsync();
      if (registered.some(task => typeof task.taskName === 'string' && task.taskName.startsWith('eyg-background:'))) throw new Error('OS background tasks are still registered');
      await this.edit(async () => {
        await this.save(new Map(), new Map());
        this.identities.clear();
        // No identity may reuse an OS slot while queued deliveries from this
        // JavaScript process could still target an old dispatcher.
        this.closed = true;
      });
      return { restart_required: true };
    } finally {
      this.resetting = false;
    }
  }

  async execute(name, body) {
    await this.available();
    const { task, run } = await this.edit(() => {
      this.checkOpen();
      const task = this.tasks.get(taskName(name));
      if (!task) throw new Error('Unknown background task');
      if (this.retiring.has(name)) throw new Error('Background task is being unregistered');
      if (this.active.has(task.slot)) throw new Error('Background task is already running');
      const run = { id: this.nextRun++, controller: new AbortController(), reason: null };
      this.active.set(task.slot, run);
      return { task, run };
    });
    const started_ms = this.now();
    const timer = setTimeout(() => { run.reason = 'timeout'; run.controller.abort(); }, task.timeout_ms);
    let record;
    try {
      const payload = jsonData({ data: body?.data ?? null, error: body?.error ?? null,
        execution_info: body?.executionInfo ?? {}, metadata: task.metadata }, 512 * 1024);
      const input = toSpec(payload);
      const host = this.hostFactory();
      const response = await runSession(this.native, host, task.source, undefined, undefined,
        { directory: task.directory ?? this.directory, ...this.nativeOptions, input }, run.controller.signal);
      if (response.status === 'cancelled') record = { status: run.reason === 'timeout' ? 'timeout' : 'cancelled', reason: run.reason };
      else if (response.status === 'done' && response.result?.value) record = { status: 'done', value: fromSpec(response.result.value) };
      else record = { status: 'error', error: JSON.stringify(response) };
      record = jsonData(record, MAX_RESULT);
    } catch (error) {
      record = { status: 'error', error: (error instanceof Error ? error.message : String(error)).slice(0, 4096) };
    } finally {
      clearTimeout(timer);
    }
    record = { ...record, name: task.name, task_name: slotName(task.slot), run_id: run.id, started_ms, finished_ms: this.now() };
    try {
      await this.edit(async () => {
        // Replaced/unregistered entrypoints cannot recreate stale results, and
        // completion from an old VM cannot release a new invocation's slot.
        if (this.tasks.get(task.name) === task && this.active.get(task.slot) === run) {
          await this.storage.setItem(resultKey(task.name), JSON.stringify(record));
        }
      });
      return record;
    } finally {
      await this.edit(() => { if (this.active.get(task.slot) === run) this.active.delete(task.slot); });
    }
  }

  close() {
    this.closed = true;
    for (const slot of this.active.keys()) this.abort(slot, 'closed');
  }
}
