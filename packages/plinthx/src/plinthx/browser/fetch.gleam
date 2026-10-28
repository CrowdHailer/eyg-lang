//// Fetch: https://fetch.spec.whatwg.org/

import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option}
import plinthx/browser/abort_signal.{type AbortSignal}

pub type Fetch

pub type Response

pub type Request

pub type ResponseConstructor

@external(javascript, "./fetch_ffi.mjs", "getResponse")
pub fn get_response() -> Result(ResponseConstructor, Nil)

@external(javascript, "./fetch_ffi.mjs", "newResponse")
pub fn new_response(
  constructor: ResponseConstructor,
  body: String,
  status: Int,
  headers: List(#(String, String)),
) -> Result(Response, String)

@external(javascript, "./fetch_ffi.mjs", "newResponseBits")
pub fn new_response_bits(
  constructor: ResponseConstructor,
  body: BitArray,
  status: Int,
  headers: List(#(String, String)),
) -> Result(Response, String)

@external(javascript, "./fetch_ffi.mjs", "newEmptyResponse")
pub fn new_empty_response(
  constructor: ResponseConstructor,
  status: Int,
  headers: List(#(String, String)),
) -> Result(Response, String)

@external(javascript, "./fetch_ffi.mjs", "requestUrl")
pub fn request_url(request: Request) -> String

@external(javascript, "./fetch_ffi.mjs", "requestMethod")
pub fn request_method(request: Request) -> String

@external(javascript, "./fetch_ffi.mjs", "requestHeaders")
pub fn request_headers(request: Request) -> List(#(String, String))

@external(javascript, "./fetch_ffi.mjs", "requestBytes")
pub fn request_bytes(request: Request) -> Promise(Result(BitArray, String))

@external(javascript, "./fetch_ffi.mjs", "requestHeader")
pub fn request_header(request: Request, name: String) -> Option(String)

@external(javascript, "./fetch_ffi.mjs", "text")
pub fn request_text(request: Request) -> Promise(Result(String, String))

pub type RequestInit {
  RequestInit(
    method: String,
    headers: List(#(String, String)),
    body: String,
    signal: Option(AbortSignal),
  )
}

@external(javascript, "./fetch_ffi.mjs", "get")
pub fn get() -> Result(Fetch, Nil)

@external(javascript, "./fetch_ffi.mjs", "send")
pub fn send(
  fetch: Fetch,
  url: String,
  init: RequestInit,
) -> Promise(Result(Response, String))

@external(javascript, "./fetch_ffi.mjs", "status")
pub fn status(response: Response) -> Int

@external(javascript, "./fetch_ffi.mjs", "text")
pub fn text(response: Response) -> Promise(Result(String, String))
