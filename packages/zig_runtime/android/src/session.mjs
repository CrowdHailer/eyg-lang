import { fromSpec, resultSpec } from './effects.mjs';

// Native evaluate/resume run on the Kotlin module's IO dispatcher, off the UI thread.
// The signal belongs to this run, never to the serialized EYG request.
export async function runSession(native, host, source, onUpdate, cancelled = () => false, options = {}, signal) {
  const stopped = Symbol('cancelled');
  const isCancelled = () => signal?.aborted || cancelled();
  let stop;
  const aborted = new Promise(resolve => { stop = () => resolve(stopped); });
  signal?.addEventListener('abort', stop, { once: true });
  if (signal?.aborted) stop();
  let id, destruction, finished = false, wasCancelled = false;
  const attempt = operation => {
    try { return Promise.resolve(operation()); }
    catch (error) { return Promise.reject(error); }
  };
  const destroy = () => {
    if (id === undefined) return Promise.resolve();
    destruction ??= attempt(() => native.destroy(id));
    return destruction;
  };
  const wait = async operation => {
    if (isCancelled()) throw stopped;
    // Promise.race observes even a late rejection from abandoned native/SDK IO.
    const value = await Promise.race([attempt(operation), aborted]);
    if (value === stopped || isCancelled()) throw stopped;
    return value;
  };
  try {
    await wait(() => attempt(() => native.create()).then(value => {
      id = value;
      // Abort can win while creation is still running on Kotlin's IO worker.
      if (finished) destroy().catch(() => {});
      return value;
    }));
    let response = JSON.parse(await wait(() => native.evaluate(id, JSON.stringify({ source, ...options }))));
    while (response.status === 'effect') {
      const effect = response.effect;
      onUpdate?.({ status: 'effect', label: effect.label });
      let reply;
      try {
        const value = await wait(() => host.perform(effect.label, fromSpec(effect.value)));
        reply = resultSpec(true, value);
      } catch (error) {
        if (error === stopped || isCancelled()) throw stopped;
        reply = resultSpec(false, error instanceof Error ? error.message : String(error));
      }
      response = JSON.parse(await wait(() => native.resume(id, JSON.stringify(reply))));
    }
    return response;
  } catch (error) {
    if (error !== stopped && !isCancelled()) throw error;
    wasCancelled = true;
    return { status: 'cancelled' };
  } finally {
    finished = true;
    const closing = attempt(() => host.close());
    const destroying = destroy();
    closing.catch(() => {});
    destroying.catch(() => {});
    try {
      // Kotlin retires the ID immediately; an active native call retains its
      // pointer until it returns. Neither network IO nor SDK disposal blocks UI.
      if (wasCancelled || isCancelled()) return { status: 'cancelled' };
      await wait(() => Promise.all([closing, destroying]));
    } catch (error) {
      if (error === stopped || isCancelled()) return { status: 'cancelled' };
      throw error;
    } finally {
      signal?.removeEventListener('abort', stop);
    }
  }
}
