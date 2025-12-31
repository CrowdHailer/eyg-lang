//// This module is extracted from workspace/state to reduce the number or imports and to separate
//// this Effect type from the Effect type in workspace/state

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/cast
import gleam/list
import website/harness/browser/alert
import website/harness/browser/file/read as read_file

pub type Effect {
  Alert(String)
  Open(String)
  ReadFile(file: String)
}

pub fn cast(label, input) {
  case list.key_find(lookup(), label) {
    Ok(#(_, cast)) -> cast(input)
    Error(Nil) -> Error(break.UnhandledEffect(label, input))
  }
}

fn lookup() {
  [
    // #(abort.l, #(#(abort.lift, abort.reply), abort.cast)),
    #(alert.l, #(#(alert.lift, alert.reply), alert.cast |> cast.map(Alert))),
    // #(copy.l, #(#(copy.lift, copy.reply()), copy.cast)),
    // #(download.l, #(#(download.lift, download.reply()), download.cast)),
    // #(flip.l, #(#(flip.lift, flip.reply()), flip.cast)),
    // #(fetch.l, #(#(fetch.lift(), fetch.lower()), fetch.cast)),
    // #(follow.l, #(#(follow.lift(), follow.lower()), follow.cast)),
    // // #(fs_list.l, #(#(fs_list.lift, fs_list.lower()), fs_list.cast)),
    #("Open", #(
      #(t.String, t.result(t.unit, t.unit)),
      cast.as_string |> cast.map(Open),
    )),
    #(read_file.l, #(
      #(read_file.lift, read_file.lower()),
      read_file.cast |> cast.map(ReadFile),
    )),
    // #(geo.l, #(#(geo.lift, geo.lower()), geo.cast)),
  // #(now.l, #(#(now.lift, now.reply), now.cast)),
  // #(paste.l, #(#(paste.lift, paste.reply()), paste.cast)),
  // #(prompt.l, #(#(prompt.lift, prompt.reply()), prompt.cast)),
  // #(random.l, #(#(random.lift, random.lower), random.cast)),
  // #(visit.l, #(#(visit.lift, visit.reply()), visit.cast)),
  ]
}
