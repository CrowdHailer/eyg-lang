import harness/fetch
import harness/impl/browser/abort
import harness/impl/browser/alert
import harness/impl/browser/copy
import harness/impl/browser/download
import harness/impl/browser/flip
import harness/impl/browser/geolocation as geo
import harness/impl/browser/now
import harness/impl/browser/paste
import harness/impl/browser/prompt
import harness/impl/browser/random
import harness/impl/browser/visit

pub fn effects() {
  [
    #(abort.l, #(abort.lift, abort.reply, abort.blocking)),
    #(alert.l, #(alert.lift, alert.reply, alert.blocking)),
    #(copy.l, #(copy.lift, copy.reply(), copy.blocking)),
    #(download.l, #(download.lift, download.reply(), download.blocking)),
    #(flip.l, #(flip.lift, flip.reply(), flip.blocking)),
    #(fetch.l, #(fetch.lift(), fetch.lower(), fetch.blocking)),
    // #(fs_list.l, #(fs_list.lift, fs_list.lower(), fs_list.blocking)),
    // #(fs_read.l, #(fs_read.lift, fs_read.lower(), fs_read.blocking)),
    #(geo.l, #(geo.lift, geo.lower(), geo.blocking)),
    #(now.l, #(now.lift, now.reply, now.blocking)),
    #(paste.l, #(paste.lift, paste.reply(), paste.blocking)),
    #(prompt.l, #(prompt.lift, prompt.reply(), prompt.blocking)),
    #(random.l, #(random.lift, random.reply(), random.blocking)),
    #(visit.l, #(visit.lift, visit.reply(), visit.blocking)),
  ]
}
