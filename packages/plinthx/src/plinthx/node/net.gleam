//// Native Node Unix sockets, suitable for local service control protocols.

import gleam/javascript/promise.{type Promise}

pub type Socket

@external(javascript, "./net_ffi.mjs", "connectUnix")
pub fn connect_unix(path: String) -> Promise(Result(Socket, String))

@external(javascript, "./net_ffi.mjs", "onData")
pub fn on_data(socket: Socket, callback: fn(String) -> Nil) -> Nil

@external(javascript, "./net_ffi.mjs", "onError")
pub fn on_error(socket: Socket, callback: fn(String) -> Nil) -> Nil

@external(javascript, "./net_ffi.mjs", "write")
pub fn write(socket: Socket, text: String) -> Result(Nil, String)

@external(javascript, "./net_ffi.mjs", "close")
pub fn close(socket: Socket) -> Nil
