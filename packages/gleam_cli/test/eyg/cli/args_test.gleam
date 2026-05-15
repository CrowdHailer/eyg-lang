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

pub fn run_stdin_test() {
  assert args.Run(source.Stdin) == args.parse(["run", "-"])
}

pub fn run_stdin_long_flag_test() {
  assert args.Run(source.Stdin) == args.parse(["run", "--stdin"])
}

pub fn eval_code_test() {
  let code = "!int_add(1, 1)"
  assert args.Eval(source.Code(code)) == args.parse(["eval", "-c", code])
}

pub fn eval_stdin_test() {
  assert args.Eval(source.Stdin) == args.parse(["eval", "-"])
}

pub fn eval_stdin_long_flag_test() {
  assert args.Eval(source.Stdin) == args.parse(["eval", "--stdin"])
}

pub fn compile_code_test() {
  let code = "!int_add(1, 1)"
  assert args.Compile(source.Code(code)) == args.parse(["compile", "-c", code])
}

pub fn compile_stdin_test() {
  assert args.Compile(source.Stdin) == args.parse(["compile", "-"])
}

pub fn compile_stdin_long_flag_test() {
  assert args.Compile(source.Stdin) == args.parse(["compile", "--stdin"])
}
