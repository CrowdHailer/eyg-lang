import website/harness/browser/abort
import website/harness/browser/alert
import website/harness/browser/copy
import website/harness/browser/download
import website/harness/browser/fetch
import website/harness/browser/flip
import website/harness/browser/geolocation as geo
import website/harness/browser/now
import website/harness/browser/paste
import website/harness/browser/prompt
import website/harness/browser/random
import website/harness/browser/visit

pub fn effects() {
  [
    // #(abort.l, #(abort.lift, abort.reply, abort.blocking)),
    #(alert.l, #(#(alert.lift, alert.reply), alert.preflight)),
    // #(copy.l, #(copy.lift, copy.reply(), copy.blocking)),
  // #(download.l, #(download.lift, download.reply(), download.blocking)),
  // #(flip.l, #(flip.lift, flip.reply(), flip.blocking)),
  // #(fetch.l, #(fetch.lift(), fetch.lower(), fetch.blocking)),
  // // #(fs_list.l, #(fs_list.lift, fs_list.lower(), fs_list.blocking)),
  // // #(fs_read.l, #(fs_read.lift, fs_read.lower(), fs_read.blocking)),
  // #(geo.l, #(geo.lift, geo.lower(), geo.blocking)),
  // #(now.l, #(now.lift, now.reply, now.blocking)),
  // #(paste.l, #(paste.lift, paste.reply(), paste.blocking)),
  // #(prompt.l, #(prompt.lift, prompt.reply(), prompt.blocking)),
  // #(random.l, #(random.lift, random.reply(), random.blocking)),
  // #(visit.l, #(visit.lift, visit.reply(), visit.blocking)),
  ]
}
