import argv
import eyg/cli/args
import eyg/cli/run
import gleam/io
import gleam/javascript/promise

pub fn main() {
  use result <- promise.map(case args.parse(argv.load().arguments) {
    args.Run(file) -> run.execute(file)
    args.Fail -> promise.resolve(Error("bad arguments"))
  })
  case result {
    Ok(message) -> io.println(message)
    Error(reason) -> io.println(reason)
  }
}
