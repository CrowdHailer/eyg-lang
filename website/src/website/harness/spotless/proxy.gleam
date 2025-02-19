import gleam/http/request.{Request}
import midas/task

pub fn proxy(task, scheme, host, port, prefix) {
  case task {
    task.Fetch(request, resume) -> {
      let request = via_proxy(request, scheme, host, port, prefix)
      task.Fetch(request, fn(x) { proxy(resume(x), scheme, host, port, prefix) })
    }
    task.Abort(_) | task.Done(_) -> task
    task.Bundle(f, m, resume) ->
      task.Bundle(f, m, fn(x) { proxy(resume(x), scheme, host, port, prefix) })
    task.Follow(lift, resume) ->
      task.Follow(lift, fn(x) { proxy(resume(x), scheme, host, port, prefix) })
    task.Hash(a, b, resume) ->
      task.Hash(a, b, fn(x) { proxy(resume(x), scheme, host, port, prefix) })
    task.List(lift, resume) ->
      task.List(lift, fn(x) { proxy(resume(x), scheme, host, port, prefix) })
    task.Log(lift, resume) ->
      task.Log(lift, fn(x) { proxy(resume(x), scheme, host, port, prefix) })
    task.Read(lift, resume) ->
      task.Read(lift, fn(x) { proxy(resume(x), scheme, host, port, prefix) })
    task.Serve(p, h, resume) ->
      task.Serve(p, h, fn(x) { proxy(resume(x), scheme, host, port, prefix) })
    task.Write(a, b, resume) ->
      task.Write(a, b, fn(x) { proxy(resume(x), scheme, host, port, prefix) })
    task.Zip(lift, resume) ->
      task.Zip(lift, fn(x) { proxy(resume(x), scheme, host, port, prefix) })
  }
}

fn via_proxy(original, scheme, host, port, prefix) {
  let Request(method, headers, body, _scheme, _host, _port, path, query) =
    original
  Request(method, headers, body, scheme, host, port, prefix <> path, query)
}
