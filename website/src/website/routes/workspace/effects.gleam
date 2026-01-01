//// This module is extracted from workspace/state to reduce the number or imports and to separate
//// this Effect type from the Effect type in workspace/state

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/cast
import gleam/http/request
import gleam/list
import gleam/uri
import website/harness/browser/abort
import website/harness/browser/alert
import website/harness/browser/copy
import website/harness/browser/decode_json
import website/harness/browser/download
import website/harness/browser/fetch
import website/harness/browser/file/read as read_file
import website/harness/browser/follow
import website/harness/browser/geolocation as geo
import website/harness/browser/now
import website/harness/browser/paste
import website/harness/browser/prompt
import website/harness/browser/random

pub type Effect {
  Abort(String)
  Alert(String)
  Copy(String)
  Open(String)
  DecodeJson(BitArray)
  Download(#(String, BitArray))
  Fetch(request.Request(BitArray))
  ReadFile(file: String)
  Follow(uri: uri.Uri)
  Geolocation
  Now
  Paste
  Prompt(message: String)
  Random(max: Int)
}

pub fn cast(label, input) {
  case list.key_find(lookup(), label) {
    Ok(#(_, cast)) -> cast(input)
    Error(Nil) -> Error(break.UnhandledEffect(label, input))
  }
}

pub fn types() {
  list.map(lookup(), fn(entry) {
    let #(key, #(types, _)) = entry
    #(key, types)
  })
}

fn lookup() {
  [
    // don't implement abort it stays as error in debug state
    #(abort.l, #(#(abort.lift, abort.reply), abort.cast |> cast.map(Abort))),
    #(alert.l, #(#(alert.lift, alert.reply), alert.cast |> cast.map(Alert))),
    #(copy.l, #(#(copy.lift, copy.reply()), copy.cast |> cast.map(Copy))),
    #(decode_json.l, #(
      #(decode_json.lift, decode_json.reply()),
      decode_json.cast |> cast.map(DecodeJson),
    )),
    #(download.l, #(
      #(download.lift, download.reply()),
      download.cast |> cast.map(Download),
    )),
    // #(flip.l, #(#(flip.lift, flip.reply()), flip.cast |> cast.map(Flip))),
    #(fetch.l, #(#(fetch.lift(), fetch.lower()), fetch.cast |> cast.map(Fetch))),
    #(follow.l, #(
      #(follow.lift(), follow.lower()),
      follow.cast |> cast.map(Follow),
    )),
    // #(fs_list.l, #(#(fs_list.lift, fs_list.lower()), fs_list.cast |> cast.map(Fs_list))),
    #("Open", #(
      #(t.String, t.result(t.unit, t.unit)),
      cast.as_string |> cast.map(Open),
    )),
    #(read_file.l, #(
      #(read_file.lift, read_file.lower()),
      read_file.cast |> cast.map(ReadFile),
    )),
    #(geo.l, #(
      #(geo.lift, geo.lower()),
      geo.cast |> cast.map(fn(_) { Geolocation }),
    )),
    #(now.l, #(#(now.lift, now.reply), now.cast |> cast.map(fn(_) { Now }))),
    #(paste.l, #(
      #(paste.lift, paste.reply()),
      paste.cast |> cast.map(fn(_) { Paste }),
    )),
    #(prompt.l, #(
      #(prompt.lift, prompt.reply()),
      prompt.cast |> cast.map(Prompt),
    )),
    #(random.l, #(#(random.lift, random.lower), random.cast |> cast.map(Random))),
    // #(visit.l, #(#(visit.lift, visit.reply()), visit.cast |> cast.map(Visit))),
  ]
}
