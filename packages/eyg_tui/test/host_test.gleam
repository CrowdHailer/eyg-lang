import eyg_tui/host
import gleam/crypto
import gleam/string
import loam/system
import midas/effect

pub fn portable_hash_and_local_clock_work_test() {
  assert host.run(system.hash(effect.Sha256, <<"abc":utf8>>))
    == Ok(crypto.hash(crypto.Sha256, <<"abc":utf8>>))
  let assert Ok(now) = host.run(system.now())
  assert now > 1_700_000_000_000
}

pub fn writes_are_errors_and_unavailable_operations_stop_test() {
  let assert Ok(Error(_)) = host.run(system.write_file("/unused", "value"))
  let assert Error(reason) = host.run(system.wait(1))
  assert string.contains(reason, "JavaScript host")
}
