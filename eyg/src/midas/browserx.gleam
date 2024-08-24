import gleam/fetch
import gleam/io
import gleam/javascript/promise
import midas/task as t

// can't be part of main midas reliance on node stuff. would need to be sub package
pub fn run(task) {
  case task {
    t.Done(value) -> promise.resolve(Ok(value))
    t.Abort(reason) -> promise.resolve(Error(reason))

    t.Fetch(request, resume) -> {
      use return <- promise.await(do_fetch(request))
      run(resume(return))
    }
    t.Log(message, resume) -> {
      io.println(message)
      run(resume(Ok(Nil)))
    }
    _ -> panic as "unsupported effect in run"
  }
}

pub fn do_fetch(request) {
  use response <- promise.await(fetch.send_bits(request))
  let assert Ok(response) = response
  use response <- promise.await(fetch.read_bytes_body(response))
  let response = case response {
    Ok(response) -> Ok(response)
    Error(fetch.NetworkError(s)) -> Error(t.NetworkError(s))
    Error(fetch.UnableToReadBody) -> Error(t.UnableToReadBody)
    Error(fetch.InvalidJsonBody) -> panic
  }
  promise.resolve(response)
}
