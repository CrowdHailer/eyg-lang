// The registry is injected so this boundary can be tested without a phone.
// Expo remains responsible for OS permissions; a call never implies a grant.
export class ExpoEffects {
  /** @param {Record<string, any>} modules @param {any} views */
  constructor(modules, views = null, maxEvents = 1024, options = {}) {
    if (!Number.isSafeInteger(maxEvents) || maxEvents < 1) throw new Error('Invalid event queue limit');
    this.modules = modules;
    this.views = views;
    this.maxEvents = maxEvents;
    this.handles = new Map();
    this.deferred = new Map();
    this.replies = new Map();
    this.events = [];
    this.waiters = [];
    this.nextHandle = 1;
    this.nextReply = 1;
    this.closed = false;
    this.dropped = 0;
    this.pure = options.pure;
  }

  path(object, path) {
    const explicit = Array.isArray(path);
    const parts = explicit ? path : typeof path === 'string' ? path.split('.') : [];
    let parent = null;
    for (const part of parts) {
      if (typeof part !== 'string' || (!explicit && !part) || ['__proto__', 'prototype', 'constructor'].includes(part)) {
        throw new Error('Invalid Expo member path');
      }
      parent = object;
      if (object == null || !(part in Object(object))) throw new Error(`Unknown member ${path}`);
      object = object[part];
    }
    return { parent, value: object };
  }

  async perform(label, lift) {
    if (this.closed) throw new Error('Effect session is closed');
    if (label === 'ExpoNextEvent') return this.nextEvent(lift?.timeout_ms ?? lift?.timeoutMs ?? 30000);
    if (label === 'ExpoReply') {
      if (!this.replies.has(lift.token)) throw new Error('Unknown or settled Expo callback token');
      if (('value' in lift) === ('error' in lift)) throw new Error('ExpoReply needs exactly one value or error');
      const rejected = 'error' in lift;
      const value = this.decode(rejected ? lift.error : lift.value);
      this.finishReply(lift.token, rejected, value);
      return null;
    }
    if (label === 'ExpoRelease') {
      await this.release(lift.expo_handle ?? lift.handle);
      return null;
    }
    if (label === 'ExpoView') {
      if (!this.views) throw new Error('This host has no native view surface');
      if (lift.action === 'close') return this.views.close(lift.id);
      return this.views.show(lift, (topic, args) => this.emit(topic, args));
    }
    if (label !== 'Expo') throw new Error(`Unhandled phone effect ${label}`);
    if (lift.method === '$modules') return Object.keys(this.modules).sort();
    const handle = lift.expo_handle ?? lift.handle;
    if (lift.method === '$await') return this.awaitDeferred(handle);
    const object = handle !== undefined ? this.handles.get(handle) : 'object' in lift ? this.decode(lift.object) : this.modules[lift.module];
    if (object == null) throw new Error(`Unknown Expo module or handle ${lift.module ?? handle}`);
    if (lift.method === '$members') {
      return [...new Set([...Object.keys(object), ...Object.getOwnPropertyNames(Object.getPrototypeOf(object) ?? {})])]
        .filter(x => !['__proto__', 'prototype', 'constructor'].includes(x)).sort();
    }
    const { parent, value } = this.path(object, lift.method ?? '');
    if (lift.get) return this.encode(value);
    if (typeof value !== 'function') throw new Error('Expo member is not callable; use get: True({})');
    const args = (lift.args ?? []).map(x => this.decode(x));
    const result = lift.construct ? Reflect.construct(value, args) : Reflect.apply(value, parent ?? object, args);
    if (lift.defer) return this.defer(result);
    const resolved = await result;
    if (this.closed) {
      await this.dispose(resolved);
      throw new Error('Effect session is closed');
    }
    return this.encode(resolved);
  }

  decode(value) {
    if (value instanceof Date) {
      if (!Number.isFinite(value.getTime())) throw new Error('Invalid Expo date');
      return value;
    }
    if (Array.isArray(value)) return value.map(x => this.decode(x));
    if (value && typeof value === 'object') {
      if ('expo_handle' in value) {
        if (!this.handles.has(value.expo_handle)) throw new Error('Released or unknown object handle');
        return this.handles.get(value.expo_handle);
      }
      if ('expo_callback' in value) {
        const topic = String(value.expo_callback);
        if ('expo_sync' in value) {
          if ('expo_return' in value || 'expo_reply' in value) throw new Error('Cannot combine expo_sync with another callback return mode');
          if (typeof this.pure !== 'function') throw new Error('This host has no synchronous EYG evaluator');
          if (typeof value.expo_sync !== 'string' || value.expo_sync.length > 4096) throw new Error('Invalid synchronous EYG source');
          const maxSteps = value.expo_steps ?? 1000;
          if (!Number.isSafeInteger(maxSteps) || maxSteps < 1 || maxSteps > 10000) throw new Error('Invalid synchronous EYG step budget');
          return (...args) => {
            if (this.closed) return undefined;
            pureData(args);
            const request = JSON.stringify({ source: value.expo_sync, argument: toSpec(this.encode(args)), max_steps: maxSteps });
            if (request.length > 65536) throw new Error('Synchronous EYG callback request exceeds size limit');
            const response = JSON.parse(this.pure(request));
            if (response.status !== 'done' || !response.result || !('value' in response.result)) throw new Error(`Synchronous EYG callback failed: ${JSON.stringify(response.error ?? response.result?.break ?? response)}`);
            const result = this.decode(fromSpec(response.result.value));
            if (value.expo_emit !== false) this.emit(topic, args);
            return result;
          };
        }
        if (value.expo_reply === true) {
          if ('expo_return' in value) throw new Error('Cannot combine expo_return and expo_reply');
          if (value.expo_emit === false) throw new Error('Reply callbacks must emit an event');
          const timeout = value.expo_timeout_ms ?? 30000;
          if (!Number.isSafeInteger(timeout) || timeout < 0 || timeout > 300000) throw new Error('Invalid callback timeout');
          return (...args) => this.callbackReply(topic, args, timeout);
        }
        return (...args) => {
          if (this.closed) return undefined;
          if (value.expo_emit !== false) this.emit(topic, args);
          return 'expo_return' in value ? this.decode(value.expo_return) : undefined;
        };
      }
      if ('expo_object' in value) {
        if (!Array.isArray(value.expo_object)) throw new Error('Invalid Expo object fields');
        return Object.fromEntries(value.expo_object.map(entry => {
          if (!entry || typeof entry.key !== 'string' || !('value' in entry)) throw new Error('Invalid Expo object field');
          return [entry.key, this.decode(entry.value)];
        }));
      }
      if ('expo_date' in value) return dateFromISO(value.expo_date);
      if ('expo_bytes' in value) return Uint8Array.from(value.expo_bytes);
      if ('expo_number' in value) {
        const number = Number(value.expo_number);
        if (typeof value.expo_number !== 'string' || value.expo_number.trim() === '' || !Number.isFinite(number)) throw new Error('Invalid phone number');
        return number;
      }
      return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, this.decode(v)]));
    }
    return value;
  }

  encode(value, seen = new Set()) {
    if (value == null) return null;
    if (typeof value === 'number' && !Number.isFinite(value)) throw new Error('Non-finite Expo result');
    if (typeof value === 'number') return Number.isSafeInteger(value) ? value : { expo_number: String(value) };
    if (['string', 'boolean'].includes(typeof value)) return value;
    if (value instanceof Date) {
      if (!Number.isFinite(value.getTime())) throw new Error('Invalid Expo date');
      return { expo_date: value.toISOString() };
    }
    if (ArrayBuffer.isView(value)) return { expo_bytes: Array.from(new Uint8Array(value.buffer, value.byteOffset, value.byteLength)) };
    if (value instanceof ArrayBuffer) return { expo_bytes: Array.from(new Uint8Array(value)) };
    if (Array.isArray(value) && !seen.has(value)) {
      seen.add(value);
      const result = value.map(x => this.encode(x, seen));
      seen.delete(value);
      return result;
    }
    if (typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype && !seen.has(value) && !Object.values(value).some(x => typeof x === 'function')) {
      seen.add(value);
      const result = Object.fromEntries(Object.entries(value).map(([k, v]) => [k, this.encode(v, seen)]));
      seen.delete(value);
      return result;
    }
    for (const [id, existing] of this.handles) if (existing === value) return { expo_handle: id };
    const id = this.nextHandle++;
    this.handles.set(id, value);
    return { expo_handle: id };
  }

  emit(topic, args, extra = {}) {
    if (this.closed) return;
    const event = { topic, args: this.encode(args), dropped: this.dropped, ...extra };
    const waiter = this.waiters.shift();
    if (waiter) waiter(event);
    else {
      if (this.events.length === this.maxEvents) {
        const dropped = this.events.shift();
        this.dropped++;
        if (dropped.callback_token !== undefined) this.finishReply(dropped.callback_token, true, new Error('Expo callback event dropped'));
      }
      this.events.push(event);
    }
  }

  callbackReply(topic, args, timeout) {
    if (this.closed || this.replies.size >= this.maxEvents) {
      const promise = Promise.reject(new Error(this.closed ? 'Effect session is closed' : 'Too many pending Expo callbacks'));
      promise.catch(() => {});
      return promise;
    }
    const token = this.nextReply++;
    const promise = new Promise((resolve, reject) => {
      const timer = setTimeout(() => this.finishReply(token, true, new Error('Expo callback timed out')), timeout);
      this.replies.set(token, { resolve, reject, timer });
    });
    // Foreign SDKs sometimes ignore a callback's return value. Keep rejected
    // callbacks observed while preserving their rejection for actual awaiters.
    promise.catch(() => {});
    try { this.emit(topic, args, { callback_token: token }); }
    catch (error) { this.finishReply(token, true, error); }
    return promise;
  }

  finishReply(token, rejected, value) {
    const pending = this.replies.get(token);
    if (!pending) return;
    this.replies.delete(token);
    clearTimeout(pending.timer);
    if (rejected) pending.reject(value);
    else pending.resolve(value);
  }

  defer(result) {
    const promise = Promise.resolve(result);
    for (const [id, object] of this.handles) {
      if (object === promise && this.deferred.has(id)) return { expo_handle: id };
    }
    const id = this.nextHandle++;
    let cancel;
    const cancelled = new Promise(resolve => { cancel = () => resolve({ cancelled: true }); });
    const state = { released: false, settled: false, resolved: false, transferred: false, value: undefined, disposal: null, cancel, cancelled, completion: null };
    // Both branches fulfill the tracked outcome. A deferred SDK rejection must
    // not become an unhandled rejection before EYG reaches $await.
    state.completion = promise.then(value => {
      state.settled = true;
      state.resolved = true;
      state.value = value;
      if (state.released) return this.disposeDeferred(state).then(() => ({ ok: true, value }), error => ({ ok: false, error }));
      return { ok: true, value };
    }, error => {
      state.settled = true;
      return { ok: false, error };
    });
    this.handles.set(id, promise);
    this.deferred.set(id, state);
    return { expo_handle: id };
  }

  async awaitDeferred(id) {
    const state = this.deferred.get(id);
    if (!state || !this.handles.has(id)) throw new Error('Unknown or consumed deferred Expo handle');
    this.handles.delete(id);
    try {
      const outcome = await Promise.race([state.completion, state.cancelled]);
      if (outcome.cancelled || state.released || this.closed) throw new Error('Deferred Expo call was released or closed');
      if (!outcome.ok) throw outcome.error;
      try {
        const value = this.encode(outcome.value);
        state.transferred = true;
        return value;
      } catch (error) {
        await this.disposeDeferred(state);
        throw error;
      }
    } finally {
      this.deferred.delete(id);
    }
  }

  disposeDeferred(state) {
    if (state.transferred || !state.resolved) return Promise.resolve();
    if (!state.disposal) state.disposal = Promise.resolve().then(() => this.dispose(state.value));
    return state.disposal;
  }

  nextEvent(timeoutMs) {
    if (!Number.isFinite(timeoutMs) || timeoutMs < 0 || timeoutMs > 300000) throw new Error('Invalid event timeout');
    if (this.events.length) return Promise.resolve({ ...this.events.shift(), dropped: this.dropped });
    return new Promise(resolve => {
      const finish = event => { clearTimeout(timer); resolve(event); };
      const timer = setTimeout(() => {
        this.waiters = this.waiters.filter(x => x !== finish);
        resolve(null);
      }, timeoutMs);
      this.waiters.push(finish);
    });
  }

  async release(id) {
    const object = this.handles.get(id);
    this.handles.delete(id);
    const state = this.deferred.get(id);
    if (state) {
      this.deferred.delete(id);
      state.released = true;
      state.cancel();
      if (state.settled) await this.disposeDeferred(state);
      return;
    }
    await this.dispose(object);
  }

  async dispose(object) {
    if (typeof object?.remove === 'function') await object.remove();
    else if (typeof object?.release === 'function') await object.release();
    else if (typeof object?.closeAsync === 'function') await object.closeAsync();
    else if (typeof object?.close === 'function') await object.close();
  }

  async close() {
    if (this.closed) return;
    this.closed = true;
    for (const token of [...this.replies.keys()]) this.finishReply(token, true, new Error('Effect session is closed'));
    for (const waiter of this.waiters.splice(0)) waiter(null);
    const results = await Promise.allSettled([...new Set([...this.handles.keys(), ...this.deferred.keys()])].map(id => this.release(id)));
    this.events = [];
    this.views?.clear();
    return results;
  }
}

function pureData(value, seen = new Set(), depth = 0, budget = { remaining: 32768 }) {
  budget.remaining -= typeof value === 'string' ? 16 + value.length * 2 : 16;
  if (budget.remaining < 0) throw new Error('Synchronous EYG callback data exceeds size limit');
  if (depth > 64) throw new Error('Synchronous EYG callback data exceeds depth limit');
  if (value == null || ['string', 'boolean', 'number'].includes(typeof value)) return;
  if (value instanceof Date) return;
  if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) {
    // Encoding creates one EYG integer node per byte; charge that expansion
    // before constructing expo_bytes or the native request JSON.
    budget.remaining -= value.byteLength * 16;
    if (budget.remaining < 0) throw new Error('Synchronous EYG callback binary data exceeds size limit');
    return;
  }
  if (typeof value !== 'object' || seen.has(value) || (!Array.isArray(value) && Object.getPrototypeOf(value) !== Object.prototype)) throw new Error('Synchronous EYG callbacks accept only data arguments');
  seen.add(value);
  for (const key in value) if (Object.hasOwn(value, key)) {
    budget.remaining -= key.length * 2;
    pureData(value[key], seen, depth + 1, budget);
  }
  seen.delete(value);
}

function dateFromISO(value) {
  const match = typeof value === 'string' && /^([+-]\d{6}|\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2}))?$/.exec(value);
  if (!match) throw new Error('Invalid Expo date');
  const [, year, month, day, hour = '0', minute = '0', second = '0'] = match;
  const leap = +year % 4 === 0 && (+year % 100 !== 0 || +year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][+month - 1];
  const date = new Date(value);
  if (!days || +day < 1 || +day > days || +hour > 23 || +minute > 59 || +second > 59 || !Number.isFinite(date.getTime())) throw new Error('Invalid Expo date');
  return date;
}

export function fromSpec(value) {
  if ('integer' in value) {
    if (typeof value.integer !== 'number' || !Number.isFinite(value.integer) || !Number.isInteger(value.integer)) throw new Error('Phone effects require finite integer data');
    return value.integer;
  }
  if ('float' in value) return value.float;
  if ('string' in value) return value.string;
  if ('list' in value) return value.list.map(fromSpec);
  if ('record' in value) return Object.fromEntries(Object.entries(value.record).map(([k, v]) => [k, fromSpec(v)]));
  if ('binary' in value) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const data = value.binary['/'].bytes;
    let bits = 0, count = 0;
    const bytes = [];
    for (const char of data) {
      if (char === '=') break;
      const digit = alphabet.indexOf(char);
      if (digit < 0) throw new Error('Invalid binary effect payload');
      bits = (bits << 6) | digit; count += 6;
      if (count >= 8) { count -= 8; bytes.push((bits >> count) & 255); }
    }
    return { expo_bytes: bytes };
  }
  if ('tagged' in value) {
    const { label, value: inner } = value.tagged;
    if (label === 'True') return true;
    if (label === 'False') return false;
    if (label === 'None' || label === 'Null') return null;
    return { tag: label, value: fromSpec(inner) };
  }
  throw new Error('Phone effects only accept data values');
}

export function toSpec(value) {
  if (value == null) return { tagged: { label: 'None', value: { record: {} } } };
  if (typeof value === 'boolean') return { tagged: { label: value ? 'True' : 'False', value: { record: {} } } };
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error('Non-finite phone number');
    if (!Number.isSafeInteger(value)) return toSpec({ expo_number: String(value) });
    return { integer: value };
  }
  if (typeof value === 'string') return { string: value };
  if (Array.isArray(value)) return { list: value.map(toSpec) };
  return { record: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, toSpec(v)])) };
}

export function resultSpec(ok, value) {
  return { tagged: { label: ok ? 'Ok' : 'Error', value: toSpec(value) } };
}
