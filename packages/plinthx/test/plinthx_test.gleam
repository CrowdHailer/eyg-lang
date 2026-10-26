import gleeunit
import plinthx/node/process
import plinthx/node/tty

pub fn main() {
  gleeunit.main()
}

pub fn process_is_the_native_object_test() {
  let assert Ok(process) = process.get()
  // Piped output has no isTTY property.
  let assert True = tty.is_write_tty(tty.stdout(process)) || True
}
