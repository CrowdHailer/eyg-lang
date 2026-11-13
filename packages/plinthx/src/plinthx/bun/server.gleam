//// Bun HTTP server: https://bun.sh/docs/api/http

import gleam/javascript/promise.{type Promise}
import plinthx/browser/fetch.{type Request, type Response}
import plinthx/bun/runtime.{type Bun}

pub type Server

pub type Options {
  Options(port: Int, hostname: String, fetch: fn(Request) -> Promise(Response))
}

@external(javascript, "./server_ffi.mjs", "serve")
pub fn serve(bun: Bun, options: Options) -> Result(Server, String)

@external(javascript, "./server_ffi.mjs", "port")
pub fn port(server: Server) -> Int

@external(javascript, "./server_ffi.mjs", "stop")
pub fn stop(server: Server, force: Bool) -> Promise(Result(Nil, String))
