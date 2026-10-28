//// Bun.build and BuildArtifact: https://bun.sh/docs/bundler

import gleam/javascript/promise.{type Promise}
import plinthx/bun/runtime.{type Bun}

pub type Build

pub type Artifact

@external(javascript, "./bundle_ffi.mjs", "build")
pub fn build(bun: Bun, options: String) -> Promise(Result(Build, String))

@external(javascript, "./bundle_ffi.mjs", "success")
pub fn success(build: Build) -> Bool

@external(javascript, "./bundle_ffi.mjs", "logs")
pub fn logs(build: Build) -> List(String)

@external(javascript, "./bundle_ffi.mjs", "outputs")
pub fn outputs(build: Build) -> List(Artifact)

@external(javascript, "./bundle_ffi.mjs", "text")
pub fn text(artifact: Artifact) -> Promise(String)
