import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict
import gleam/json
import gleam/string
import multiformats/cid/v1
import overlay/eval/module

pub fn relative_imports_become_content_references_test() {
  let assert Ok(loaded) =
    module.load("test/fixtures/packages/greeting/index.eyg")
  assert 2 == dict.size(loaded.blocks)
  let assert Ok(block) = dict.get(loaded.blocks, v1.to_string(loaded.cid))
  let assert Ok(index) = json.parse_bits(block, dag_json.decoder(Nil))
  assert loaded.cid == module.cid(index)

  let assert [ir.Content(words)] = ir.list_references(index)
  let assert Ok(block) = dict.get(loaded.blocks, v1.to_string(words))
  let assert Ok(words_tree) = json.parse_bits(block, dag_json.decoder(Nil))
  assert words == module.cid(words_tree)
  assert [] == ir.list_references(words_tree)
}

pub fn dag_json_modules_load_test() {
  let assert Ok(loaded) =
    module.load("test/fixtures/packages/numbers/index.eyg.json")
  assert [v1.to_string(loaded.cid)] == dict.keys(loaded.blocks)
  assert module.cid(ir.integer(5)) == loaded.cid
}

pub fn source_loads_relative_to_a_directory_test() {
  let assert Ok(loaded) =
    module.from_source(
      "import \"./greeting/index.eyg\"",
      "test/fixtures/packages",
    )
  assert 3 == dict.size(loaded.blocks)
}

pub fn missing_and_cyclic_imports_fail_test() {
  let assert Error(reason) =
    module.from_source("import \"./nothing.eyg\"", "test/fixtures")
  assert string.contains(reason, "nothing.eyg")
  let assert Error(reason) = module.load("test/fixtures/cycle/a.eyg")
  assert string.starts_with(reason, "import cycle through ")
}

pub fn workspace_modules_load_from_memory_test() {
  let files = [
    #("src/greet.eyg", <<"let w = import \"./words.eyg\" w.hello">>),
    #("src/words.eyg", <<"{hello: \"Hello\"}">>),
  ]
  let assert Ok(loaded) = module.load_from(files, "src/greet.eyg")
  assert 2 == dict.size(loaded.blocks)
  let assert Error(reason) = module.load_from(files, "src/missing.eyg")
  assert string.contains(reason, "there is no file at src/missing.eyg")
}
