import birdie
import eyg/parser

fn snap_error(source: String) -> String {
  case parser.all_from_string(source) {
    Error(reason) -> parser.format_error(reason, source)
    Ok(_) -> panic as { "expected a parse error for: " <> source }
  }
}

pub fn missing_equals_test() {
  snap_error("let x 5")
  |> birdie.snap(title: "missing equals in let binding")
}

pub fn missing_equals_multiline_test() {
  snap_error("let x\n5")
  |> birdie.snap(title: "missing equals — multiline let binding")
}

pub fn missing_arrow_test() {
  snap_error("(x) { x }")
  |> birdie.snap(title: "missing arrow in function definition")
}

pub fn missing_brace_after_arrow_test() {
  snap_error("(x) -> x")
  |> birdie.snap(title: "missing opening brace after arrow")
}

pub fn unclosed_function_body_test() {
  snap_error("(x) -> { x")
  |> birdie.snap(title: "unclosed function body")
}

pub fn perform_lowercase_test() {
  snap_error("perform log")
  |> birdie.snap(title: "perform with lowercase effect name")
}

pub fn perform_missing_name_test() {
  snap_error("perform")
  |> birdie.snap(title: "perform with no effect name")
}

pub fn handle_lowercase_test() {
  snap_error("handle log")
  |> birdie.snap(title: "handle with lowercase effect name")
}

pub fn handle_missing_name_test() {
  snap_error("handle")
  |> birdie.snap(title: "handle with no effect name")
}

pub fn builtin_missing_name_test() {
  snap_error("!")
  |> birdie.snap(title: "bang with no builtin name")
}

pub fn builtin_uppercase_name_test() {
  snap_error("!IntAdd")
  |> birdie.snap(title: "bang with uppercase builtin name")
}

pub fn invalid_cid_test() {
  snap_error("#notacid")
  |> birdie.snap(title: "hash with invalid CID")
}

pub fn invalid_release_version_test() {
  snap_error("@standard:")
  |> birdie.snap(title: "named release with missing version")
}

pub fn invalid_release_version_word_test() {
  snap_error("@standard:foo")
  |> birdie.snap(title: "named release with non-integer version")
}

pub fn invalid_pinned_release_test() {
  snap_error("@standard:3:notacid")
  |> birdie.snap(title: "pinned release with invalid CID")
}

pub fn invalid_import_path_test() {
  snap_error("import foo")
  |> birdie.snap(title: "import with non-string path")
}

pub fn invalid_import_number_test() {
  snap_error("import 42")
  |> birdie.snap(title: "import with number instead of string")
}

pub fn unexpected_character_test() {
  snap_error(" `x")
  |> birdie.snap(title: "unexpected character backtick")
}

pub fn unexpected_plus_test() {
  snap_error("5 + 3")
  |> birdie.snap(title: "infix plus is not valid EYG syntax")
}

pub fn unterminated_string_test() {
  snap_error(" \"hello world")
  |> birdie.snap(title: "unterminated string literal")
}

pub fn invalid_escape_test() {
  snap_error(" \"\\q\"")
  |> birdie.snap(title: "invalid escape sequence in string")
}

pub fn trailing_tokens_test() {
  snap_error("5 6")
  |> birdie.snap(title: "trailing tokens after complete expression")
}

pub fn unexpected_end_test() {
  case parser.all_from_string("let x =") {
    Error(reason) ->
      parser.format_error(reason, "let x =")
      |> birdie.snap(title: "unexpected end after let equals")
    Ok(_) -> panic as "expected error"
  }
}

pub fn unclosed_lambda_args_test() {
  snap_error("(x")
  |> birdie.snap(title: "unclosed lambda parameter list")
}

pub fn multiline_error_test() {
  snap_error("let x = 5\nlet y = 10\nperform log")
  |> birdie.snap(title: "error on third line of multiline program")
}

pub fn let_after_expression_test() {
  snap_error("let x = 1\n3\nlet y = 5\n{}")
  |> birdie.snap(title: "let after expression")
}
