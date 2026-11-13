import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import opencode_plugin/tools

fn data(text) {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

pub fn labels_and_parameter_names_follow_the_effect_conventions_test() {
  assert tools.label("read") == "Read"
  assert tools.label("mcp__github__search") == "McpGithubSearch"
  assert tools.snake("filePath") == "file_path"
  assert tools.snake("oldText") == "old_text"
  assert tools.snake("HTTPServer") == "httpserver"
}

const schema =
  "{\"type\":\"object\",\"required\":[\"filePath\",\"edits\"],\"properties\":{
  \"filePath\":{\"type\":\"string\"},
  \"edits\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"oldText\",\"newText\"],\"properties\":{
    \"oldText\":{\"type\":\"string\"},\"newText\":{\"type\":\"string\"},\"allMatches\":{\"type\":\"boolean\"}
  }}},\"limit\":{\"type\":[\"number\",\"null\"]}
}}"

pub fn schemas_describe_nested_records_lists_and_optional_fields_test() {
  assert tools.type_(data(schema))
    == "{edits: List({all_matches?: True({}) | False({}), new_text: String, old_text: String}), file_path: String, limit?: Integer}"
  assert tools.type_(data(
      "{\"anyOf\":[{\"type\":\"integer\"},{\"type\":\"string\"}]}",
    ))
    == "Integer"
  assert tools.type_(data(
      "{\"type\":\"array\",\"items\":[{\"type\":\"string\"}]}",
    ))
    == "List(String)"
  assert tools.type_(dynamic.string("unknown")) == "Any"
}

pub fn nested_edit_arguments_recover_the_native_schema_names_test() {
  let input =
    data(
      "{\"file_path\":\"notes.md\",\"edits\":[{\"old_text\":\"before\",\"new_text\":\"after\",\"all_matches\":true}],\"limit\":null}",
    )
  let expected =
    data(
      "{\"filePath\":\"notes.md\",\"edits\":[{\"oldText\":\"before\",\"newText\":\"after\",\"allMatches\":true}]}",
    )
  assert tools.argument(input, data(schema)) == expected
  assert tools.result(expected)
    == data(
      "{\"file_path\":\"notes.md\",\"edits\":[{\"old_text\":\"before\",\"new_text\":\"after\",\"all_matches\":true}]}",
    )
}
