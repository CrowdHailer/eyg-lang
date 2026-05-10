//// The version string printed by `eyg --version`.
////
//// Bumped manually alongside hex releases of `eyg_cli`. Kept here rather
//// than read from `gleam.toml` because `gleam.toml` isn't available at
//// runtime once the binary is bundled with `bun build --compile`.

pub const string = "0.0.0"
