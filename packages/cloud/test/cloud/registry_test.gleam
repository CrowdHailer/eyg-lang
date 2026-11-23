import cloud/registry
import gleam/erlang/process
import gleam/otp/actor

fn reply_process() {
  let assert Ok(started) =
    actor.new(Nil)
    |> actor.on_message(fn(_, reply) {
      process.send(reply, Nil)
      actor.continue(Nil)
    })
    |> actor.start
  started.data
}

pub fn one_process_per_name_test() {
  let assert Ok(started) = registry.start()
  let a = registry.lookup(started.data, "a", reply_process)
  assert a == registry.lookup(started.data, "a", reply_process)
  assert a != registry.lookup(started.data, "b", reply_process)
}

pub fn restart_stopped_process_test() {
  let assert Ok(started) = registry.start()
  let a = registry.lookup(started.data, "a", reply_process)
  let assert Ok(pid) = process.subject_owner(a)
  process.kill(pid)
  let restarted = registry.lookup(started.data, "a", reply_process)
  assert a != restarted
  assert Nil == process.call(restarted, 1000, fn(reply) { reply })
}
