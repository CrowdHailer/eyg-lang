//// Browser is the API to the platform
//// It might make sense to implement a version of the effect interface built on this

import gleam/javascript/promise
import plinth/browser/clipboard

/// The browser platform effect
pub type Effect(m) {
  ReadFromClipboard(resume: fn(Result(String, String)) -> m)
  WriteToClipboard(text: String, resume: fn(Result(Nil, String)) -> m)
}

// Use an ignore event if we don't want a message
pub fn run(effect: Effect(m)) -> promise.Promise(m) {
  case effect {
    ReadFromClipboard(resume) -> {
      use result <- promise.map(clipboard.read_text())
      resume(result)
    }
    WriteToClipboard(text:, resume:) -> {
      use result <- promise.map(clipboard.write_text(text))
      resume(result)
    }
  }
}
