import gleam/dynamic.{Dynamic}
import gleam/otp/process.{Pid}
import gleam/otp/supervisor
import gleam/http/cowboy
import spotless/web/router

pub fn start(port) -> Result(Pid, Dynamic) {
  cowboy.start(router.handle(_, Nil), port)
  |> supervisor.to_erlang_start_result()
}