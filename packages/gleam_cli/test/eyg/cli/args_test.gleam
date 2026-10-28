import eyg/cli/args
import gleam/option.{None, Some}
import gleam/string
import loam/source

pub fn recorded_shell_test() {
  assert args.parse(["record", "shell"]) == args.RecordShell
}

pub fn run_test() {
  let file = "example.eyg.json"
  assert args.Run(source.File(file)) == args.parse(["run", file])
}

pub fn trajectory_commands_test() {
  assert args.parse(["record", "run", "-c", "42"])
    == args.Record(source.Code("42"), None)
  assert args.parse(["record", "run", "main.eyg"])
    == args.Record(source.File("main.eyg"), None)
  assert args.parse(["record", "main.eyg", "hello"])
    == args.Record(source.File("main.eyg"), Some(["hello"]))
  assert args.parse(["inspect", "trace.json", "0"])
    == args.Inspect("trace.json", Some(0))
  let assert args.InvalidArguments(_) =
    args.parse(["inspect", "trace.json", "-1"])
  assert args.parse(["replay", "trace.json"]) == args.Replay("trace.json")
  assert args.parse(["upload", "trace.json"]) == args.Upload("trace.json")
}

pub fn profile_inputs_test() {
  assert args.parse(["profile", "demo.eyg"])
    == args.Profile(source.File("demo.eyg"))
  assert args.parse(["profile", "-c", "42"]) == args.Profile(source.Code("42"))
  assert args.parse(["profile", "-"]) == args.Profile(source.Stdin)
  let assert args.InvalidArguments(_) = args.parse(["profile"])
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

pub fn check_stdin_test() {
  assert args.Check(source.Stdin) == args.parse(["check", "-"])
}

pub fn check_stdin_long_flag_test() {
  assert args.Check(source.Stdin) == args.parse(["check", "--stdin"])
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

pub fn script_from_cid_test() {
  let cid = "#baguqeerat6kjk2gjedpjcv4tuh5qiozijzgbhenep5cjfbe7vgc2ehjcqlma"
  assert args.Script(source.Code(cid), []) == args.parse([cid])
}

pub fn script_from_cid_with_args_test() {
  let cid = "#baguqeerat6kjk2gjedpjcv4tuh5qiozijzgbhenep5cjfbe7vgc2ehjcqlma"
  assert args.Script(source.Code(cid), ["a", "b"])
    == args.parse([cid, "a", "b"])
}

pub fn script_from_package_test() {
  assert args.Script(source.Code("@standard"), []) == args.parse(["@standard"])
}

pub fn signatory_inspection_commands_test() {
  assert args.parse(["signatory", "list"]) == args.SignatoryList
  assert args.parse(["signatory", "show", "personal"])
    == args.SignatoryShow("personal")
  assert string.contains(args.help_text, "signatory list")
  assert string.contains(args.help_text, "signatory show <name>")
}

pub fn malformed_signatory_commands_are_not_scripts_test() {
  let assert args.InvalidArguments(message) = args.parse(["signatory", "show"])
  assert string.starts_with(message, "usage: eyg signatory initial <name>")
  assert args.parse(["script", "signatory", "list"])
    == args.Script(source.File("signatory"), ["list"])
}

pub fn overlay_without_file_shows_usage_test() {
  let assert args.InvalidArguments(message) = args.parse(["overlay"])
  assert message
    == "usage: eyg overlay <file> | eyg overlay -c <code> | eyg overlay -"
  let assert args.InvalidArguments(_) = args.parse(["overlay", "--help"])
}
