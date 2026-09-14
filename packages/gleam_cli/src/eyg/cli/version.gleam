//// The version printed by `eyg --version`.
////
//// `bin/compile` sets it from the `gleam_cli-*` tag on the commit being built.
//// Anything else, such as `gleam run` or a build of an untagged commit, is `dev`.

@external(javascript, "./version_ffi.mjs", "version")
pub fn string() -> String
