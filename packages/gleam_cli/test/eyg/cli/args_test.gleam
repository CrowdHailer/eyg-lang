import eyg/cli/args

pub fn run_test() {
  let file = "example.eyg.json"
  assert args.Run(file) == args.parse(["run", file])
}
