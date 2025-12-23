import eyg/interpreter/cast
import gleam/result
import website/harness/browser/abort
import website/harness/browser/alert
import website/harness/browser/copy
import website/harness/browser/download
import website/harness/browser/fetch
import website/harness/browser/file/read as read_file
import website/harness/browser/flip
import website/harness/browser/follow
import website/harness/browser/geolocation as geo
import website/harness/browser/now
import website/harness/browser/paste
import website/harness/browser/prompt
import website/harness/browser/random
import website/harness/browser/visit

pub fn effects() {
  [
    #(abort.l, #(#(abort.lift, abort.reply), abort.preflight)),
    #(alert.l, #(#(alert.lift, alert.reply), alert.preflight)),
    #(copy.l, #(#(copy.lift, copy.reply()), copy.preflight)),
    #(download.l, #(#(download.lift, download.reply()), download.preflight)),
    #(flip.l, #(#(flip.lift, flip.reply()), flip.preflight)),
    #(fetch.l, #(#(fetch.lift(), fetch.lower()), fetch.preflight)),
    #(follow.l, #(#(follow.lift(), follow.lower()), follow.preflight)),
    // #(fs_list.l, #(#(fs_list.lift, fs_list.lower()), fs_list.preflight)),
    // #(fs_read.l, #(#(fs_read.lift, fs_read.lower()), fs_read.preflight)),
    #(geo.l, #(#(geo.lift, geo.lower()), geo.preflight)),
    #(now.l, #(#(now.lift, now.reply), now.preflight)),
    #(paste.l, #(#(paste.lift, paste.reply()), paste.preflight)),
    #(prompt.l, #(#(prompt.lift, prompt.reply()), prompt.preflight)),
    #(random.l, #(#(random.lift, random.lower), random.preflight)),
    #(visit.l, #(#(visit.lift, visit.reply()), visit.preflight)),
  ]
}

pub type Effect {
  Alert(message: String)
  ReadFile(file: String)
}

pub fn lookup() {
  [
    // #(abort.l, #(#(abort.lift, abort.reply), abort.cast)),
    #(alert.l, #(#(alert.lift, alert.reply), alert.cast_to(Alert))),
    // #(copy.l, #(#(copy.lift, copy.reply()), copy.cast)),
    // #(download.l, #(#(download.lift, download.reply()), download.cast)),
    // #(flip.l, #(#(flip.lift, flip.reply()), flip.cast)),
    // #(fetch.l, #(#(fetch.lift(), fetch.lower()), fetch.cast)),
    // #(follow.l, #(#(follow.lift(), follow.lower()), follow.cast)),
    // // #(fs_list.l, #(#(fs_list.lift, fs_list.lower()), fs_list.cast)),
    #(read_file.l, #(
      #(read_file.lift, read_file.lower()),
      cast_to_string(ReadFile),
    )),
    // #(geo.l, #(#(geo.lift, geo.lower()), geo.cast)),
  // #(now.l, #(#(now.lift, now.reply), now.cast)),
  // #(paste.l, #(#(paste.lift, paste.reply()), paste.cast)),
  // #(prompt.l, #(#(prompt.lift, prompt.reply()), prompt.cast)),
  // #(random.l, #(#(random.lift, random.lower), random.cast)),
  // #(visit.l, #(#(visit.lift, visit.reply()), visit.cast)),
  ]
}

pub fn run(effect) {
  case effect {
    Alert(message:) -> alert.run(message)
    ReadFile(..) -> panic as "browser doesn support"
  }
}

pub fn cast_to_string(then) {
  fn(lift) {
    use message <- result.try(cast.as_string(lift))
    Ok(then(message))
  }
}
