//// Build, run and check the real nginx service with a pinned image.

import argv
import gleam/bit_array
import gleam/http
import gleam/http/request
import gleam/io
import gleam/javascript/promise
import gleam/string
import loam/system
import plinthx/node/timers
import simplifile

const name = "eyg-roadmap-njs"

const image =
  "nginx@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de"

pub fn main() {
  case argv.load().arguments {
    ["start"] -> start()
    ["stop"] -> stop()
    [] | ["check"] -> check()
    _ -> panic as "Use gleam run -m nginx -- start|stop|check"
  }
}

fn command(program, arguments) {
  let assert Ok(cwd) = simplifile.current_directory()
  system.run(system.command(program, arguments, cwd))
}

pub fn start() {
  use built <- promise.await(
    command("gleam", ["run", "-m", "compile", "--", "handler.eyg", "dist"]),
  )
  let assert Ok(_) = built
  let assert Ok(cwd) = simplifile.current_directory()
  use started <- promise.map(
    command("docker", [
      "run",
      "--detach",
      "--rm",
      "--name",
      name,
      "-p",
      "127.0.0.1:8196:8080",
      "-v",
      cwd <> "/conf/nginx.conf:/etc/nginx/nginx.conf:ro",
      "-v",
      cwd <> "/dist:/etc/nginx/njs:ro",
      image,
    ]),
  )
  let assert Ok(_) = started
  io.println("nginx listening on http://127.0.0.1:8196")
}

pub fn stop() {
  use stopped <- promise.map(command("docker", ["stop", name]))
  let assert Ok(_) = stopped
  io.println("Stopped " <> name)
}

fn fetch(method, path) {
  let assert Ok(request) = request.to("http://127.0.0.1:8196" <> path)
  request
  |> request.set_method(method)
  |> request.set_body(<<>>)
  |> system.fetch
  |> system.run
}

fn ready(attempts) {
  assert attempts > 0 as "nginx did not answer /upstream"
  use reply <- promise.await(fetch(http.Get, "/upstream"))
  case reply {
    Ok(reply) if reply.status == 200 -> promise.resolve(Nil)
    _ -> {
      use _ <- promise.await(timers.sleep(100))
      ready(attempts - 1)
    }
  }
}

fn text(body) {
  let assert Ok(body) = bit_array.to_string(body)
  body
}

pub fn check() {
  use _ <- promise.await(start())
  let outcome =
    {
      use _ <- promise.await(ready(50))
      use get <- promise.await(fetch(http.Get, "/a/b"))
      let assert Ok(get) = get
      assert get.status == 200 as text(get.body)
      assert string.contains(
        text(get.body),
        "headers, path /a/b. Upstream said: a plain nginx location",
      )
      io.println("GET /a/b -> 200 " <> text(get.body))
      use post <- promise.await(fetch(http.Post, "/a/b"))
      let assert Ok(post) = post
      assert post.status == 405
      assert text(post.body) == "Only GET is handled by EYG"
      io.println("POST /a/b -> 405 " <> text(post.body))
      use upstream <- promise.map(fetch(http.Get, "/upstream"))
      let assert Ok(upstream) = upstream
      assert upstream.status == 200
      assert text(upstream.body) == "a plain nginx location"
      Nil
    }
    |> promise.map(Ok)
    |> promise.rescue(Error)
  use outcome <- promise.await(outcome)
  use _ <- promise.map(stop())
  let assert Ok(_) = outcome
  io.println(
    "PASS actual nginx QuickJS compiled EYG, awaited subrequest and method refusal",
  )
}
