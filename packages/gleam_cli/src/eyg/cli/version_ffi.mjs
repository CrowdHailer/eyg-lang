// The Gleam compile module supplies EYG_VERSION through Bun.build.
export function version() {
  return typeof EYG_VERSION === "string" ? EYG_VERSION : "dev";
}
