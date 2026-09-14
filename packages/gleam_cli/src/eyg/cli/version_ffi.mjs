// bin/compile replaces EYG_VERSION using `bun build --define`.
export function version() {
  return typeof EYG_VERSION === "string" ? EYG_VERSION : "dev";
}
