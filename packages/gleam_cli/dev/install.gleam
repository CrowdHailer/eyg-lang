import compile
import gleam/io
import gleam/javascript/promise
import loam/system

pub fn main() {
  use _ <- promise.await(compile.main())
  use installed <- promise.map(
    system.run(system.command(
      "sudo",
      ["install", "-m", "755", "dist/eyg", "/usr/local/bin/eyg"],
      ".",
    )),
  )
  let assert Ok(_) = installed
  io.println("Installed /usr/local/bin/eyg")
}
