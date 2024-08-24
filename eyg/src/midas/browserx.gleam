import gleam/fetch
import gleam/io
import gleam/javascript/promise
import gleam/uri
import midas/task as t
import platforms/browser/windows
import plinth/browser/window
import spotless/repl/capabilities/zip

// can't be part of main midas reliance on node stuff. would need to be sub package
pub fn run(task) {
  case task {
    t.Done(value) -> promise.resolve(Ok(value))
    t.Abort(reason) -> promise.resolve(Error(reason))

    t.Fetch(request, resume) -> {
      use return <- promise.await(do_fetch(request))
      run(resume(return))
    }
    t.Follow(url, resume) -> {
      use return <- promise.await(do_follow(url))
      run(resume(uri.parse(return)))
    }
    t.Log(message, resume) -> {
      io.println(message)
      run(resume(Ok(Nil)))
    }
    t.Zip(files, resume) -> {
      use zipped <- promise.await(zip.zip(files))
      run(resume(Ok(zipped)))
    }
    _ -> {
      io.debug(task)
      panic as "unsupported effect in run"
    }
  }
}

pub fn do_fetch(request) {
  use response <- promise.await(fetch.send_bits(request))
  case response {
    Ok(response) -> {
      use response <- promise.await(fetch.read_bytes_body(response))
      let response = case response {
        Ok(response) -> Ok(response)
        Error(fetch.NetworkError(s)) -> Error(t.NetworkError(s))
        Error(fetch.UnableToReadBody) -> Error(t.UnableToReadBody)
        Error(fetch.InvalidJsonBody) -> panic
      }
      promise.resolve(response)
    }
    Error(fetch.NetworkError(s)) -> promise.resolve(Error(t.NetworkError(s)))
    Error(fetch.UnableToReadBody) -> promise.resolve(Error(t.UnableToReadBody))
    Error(fetch.InvalidJsonBody) -> panic
  }
}

fn do_follow(url) {
  let frame = #(600, 700)
  let assert Ok(popup) = windows.open(url, frame)
  receive_redirect(popup, 100)
}

pub fn receive_redirect(popup, wait) {
  use Nil <- promise.await(do_wait(wait))
  case window.location_of(popup) {
    Ok("http" <> _ as location) -> {
      window.close(popup)
      promise.resolve(location)
    }
    _ -> receive_redirect(popup, wait)
  }
}

import plinth/javascript/global

pub fn do_wait(delay) {
  promise.new(fn(resolve) {
    let timer = global.set_timeout(delay, fn() { resolve(Nil) })
    Nil
  })
}
