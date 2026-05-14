import eyg/cli/args
import eyg/cli/internal/source

pub fn run_test() {
  let file = "example.eyg.json"
  assert args.Run(source.File(file)) == args.parse(["run", file])
}

pub fn run_code_test() {
  let code = "!print(\"hello\")"
  assert args.Run(source.Code(code)) == args.parse(["run", "-c", code])
}

pub fn run_code_long_flag_test() {
  let code = "!print(\"hello\")"
  assert args.Run(source.Code(code)) == args.parse(["run", "--code", code])
}

pub fn eval_code_test() {
  let code = "!int_add(1, 1)"
  assert args.Eval(source.Code(code)) == args.parse(["eval", "-c", code])
}

pub fn compile_code_test() {
  let code = "!int_add(1, 1)"
  assert args.Compile(source.Code(code)) == args.parse(["compile", "-c", code])
}
