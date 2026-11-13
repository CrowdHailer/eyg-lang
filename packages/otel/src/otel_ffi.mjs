// Epoch time from the high resolution clock, as seconds and nanoseconds.
// performance.timeOrigin and now() are milliseconds with fractions, kept apart so Int stays precise.
export function system_time() {
  const origin = split(performance.timeOrigin);
  const elapsed = split(performance.now());
  const nanoseconds = origin[1] + elapsed[1];
  return [origin[0] + elapsed[0] + Math.floor(nanoseconds / 1e9), nanoseconds % 1e9];
}

function split(milliseconds) {
  const seconds = Math.floor(milliseconds / 1000);
  return [seconds, Math.trunc((milliseconds - seconds * 1000) * 1e6)];
}
