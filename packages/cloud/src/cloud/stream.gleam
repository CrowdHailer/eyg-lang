//// Completions streamed from an llm, so their thinking and text can be shown as they arrive.

import gleam/http/request.{type Request}
import gleam/list
import gleam/result
import gleam/uri
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/tool

@external(erlang, "cloud_stream_ffi", "post")
fn post(
  url: String,
  headers: List(#(String, String)),
  content_type: String,
  body: BitArray,
  timeout: Int,
  acc: a,
  fold: fn(a, BitArray) -> a,
) -> Result(a, String)

/// The completion of the history, `show` is given the completion so far each time more arrives.
/// A completion can take minutes, the response stops if nothing arrives for five.
pub fn complete(
  llm: provider.Llm,
  context: provider.Context,
  history: chat.History,
  show: fn(chat.Completion(tool.Call)) -> Nil,
) -> Result(chat.Completion(tool.Call), String) {
  let request = provider.stream_completion_request(llm, context, history)
  let start = #(<<>>, chat.fresh())
  send(request, start, fn(acc, part) {
    let #(remaining, completion) = acc
    let #(chunks, remaining) =
      provider.completion_chunk_parse(llm.provider, remaining, part)
    let completion = chat.append_chunks(completion, chunks)
    case chunks {
      [] -> Nil
      _ -> show(completion)
    }
    #(remaining, completion)
  })
  |> result.map_error(fn(reason) {
    "request to "
    <> uri.to_string(request.to_uri(request))
    <> " failed: "
    <> reason
  })
  |> result.map(fn(acc) { acc.1 })
}

fn send(request: Request(BitArray), acc, fold) {
  let content_type =
    request.get_header(request, "content-type")
    |> result.unwrap("application/json")
  let headers = list.filter(request.headers, fn(h) { h.0 != "content-type" })
  let url = uri.to_string(request.to_uri(request))
  post(url, headers, content_type, request.body, 300_000, acc, fold)
}
