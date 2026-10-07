import gleeunit
import plinthx/node/process
import plinthx/node/tty

pub fn main() {
  gleeunit.main()
}

pub fn process_is_the_native_object_test() {
  let assert Ok(process) = process.get()
  // Piped output has no isTTY property.
  let assert True = case tty.is_tty(process.stdout(process)) {
    Ok(_) | Error(Nil) -> True
  }
}
