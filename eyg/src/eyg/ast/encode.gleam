import gleam/io
import gleam/list
import eyg/ast
import eyg/ast/expression as e
import eyg/ast/pattern as p

pub external type JSON

pub external fn json_to_string(JSON) -> String =
  "../../eyg_utils.js" "json_to_string"

pub external fn json_from_string(String) -> JSON =
  "" "JSON.parse"

pub external fn unsafe_coerce(a) -> b =
  "../../eyg_utils.js" "identity"

pub fn string(value: String) -> JSON {
  unsafe_coerce(value)
}

pub fn integer(value: Int) -> JSON {
  unsafe_coerce(value)
}

external fn array(value: List(JSON)) -> JSON =
  "../../eyg_utils.js" "list_to_array"

pub external fn object(entries: List(#(String, JSON))) -> JSON =
  "../../eyg_utils.js" "entries_to_object"

fn pattern_to_json(pattern) {
  case pattern {
    p.Variable(label) ->
      object([#("node", string("Variable")), #("label", string(label))])
    p.Tuple(elements) ->
      object([
        #("node", string("Tuple")),
        #(
          "elements",
          array(list.map(
            elements,
            fn(element) {
              object([#("node", string("Bind")), #("label", string(element))])
            },
          )),
        ),
      ])
    p.Record(fields) ->
      object([
        #("node", string("Record")),
        #(
          "fields",
          array(list.map(
            fields,
            fn(field) {
              let #(key, bind) = field
              object([#("key", string(key)), #("bind", string(bind))])
            },
          )),
        ),
      ])
  }
}

pub fn to_json(ast) {
  let #(_, expression) = ast
  case expression {
    e.Binary(value) ->
      object([#("node", string("Binary")), #("value", string(value))])
    e.Tuple(elements) ->
      object([
        #("node", string("Tuple")),
        #("elements", array(list.map(elements, to_json))),
      ])
    e.Record(fields) -> {
      let fields =
        list.map(
          fields,
          fn(f) {
            let #(key, value) = f
            object([
              #("node", string("Field")),
              #("key", string(key)),
              #("value", to_json(value)),
            ])
          },
        )
      object([#("node", string("Record")), #("fields", array(fields))])
    }
    e.Variable(label) ->
      object([#("node", string("Variable")), #("label", string(label))])
    e.Let(pattern, value, then) ->
      object([
        #("node", string("Let")),
        #("pattern", pattern_to_json(pattern)),
        #("value", to_json(value)),
        #("then", to_json(then)),
      ])
    e.Function(pattern, body) ->
      object([
        #("node", string("Function")),
        #("pattern", pattern_to_json(pattern)),
        #("body", to_json(body)),
      ])
    e.Call(function, with) ->
      object([
        #("node", string("Call")),
        #("function", to_json(function)),
        #("with", to_json(with)),
      ])
    e.Case(value, branches) -> {
      let branches =
        list.map(
          branches,
          fn(branch) {
            let #(name, pattern, then) = branch
            object([
              #("node", string("Branch")),
              #("name", string(name)),
              #("pattern", pattern_to_json(pattern)),
              #("then", to_json(then)),
            ])
          },
        )
      object([
        #("node", string("Case")),
        #("value", to_json(value)),
        #("branches", array(branches)),
      ])
    }
    e.Hole -> object([#("node", string("Hole"))])
    e.Provider(config, generator, _) ->
      object([
        #("node", string("Provider")),
        #("config", string(config)),
        #("generator", string(e.generator_to_string(generator))),
      ])
  }
}

external fn entries(object: JSON) -> List(#(String, JSON)) =
  "../../eyg_utils.js" "entries_from_object"

fn assert_string(value: JSON) -> String {
  unsafe_coerce(value)
}

external fn from_array(value: JSON) -> List(JSON) =
  "../../eyg_utils.js" "list_from_array"

pub fn from_json(json: JSON) {
  assert Ok(#(node, rest)) = list.key_pop(entries(json), "node")
  // find node and order rest
  case assert_string(node) {
    "Binary" -> {
      let [#("value", value)] = rest
      ast.binary(assert_string(value))
    }
    "Tuple" -> {
      let [#("elements", elements)] = rest
      let elements = list.map(from_array(elements), from_json)
      ast.tuple_(elements)
    }
    "Record" -> {
      let [#("fields", fields)] = rest
      let fields =
        list.map(
          from_array(fields),
          fn(f) {
            let [#("node", _), #("key", key), #("value", value)] = entries(f)
            #(assert_string(key), from_json(value))
          },
        )
      ast.row(fields)
    }
    "Variable" -> {
      let [#("label", label)] = rest
      ast.variable(assert_string(label))
    }

    "Let" -> {
      let [#("pattern", pattern), #("value", value), #("then", then)] = rest
      let pattern = pattern_from_json(pattern)
      let value = from_json(value)
      let then = from_json(then)
      ast.let_(pattern, value, then)
    }
    "Function" -> {
      let [#("pattern", pattern), #("body", body)] = rest
      let pattern = pattern_from_json(pattern)
      let body = from_json(body)
      ast.function(pattern, body)
    }
    "Call" -> {
      let [#("function", function), #("with", with)] = rest
      let function = from_json(function)
      let with = from_json(with)
      ast.call(function, with)
    }
    "Case" -> {
      let [#("value", value), #("branches", branches)] = rest
      let value = from_json(value)
      let branches =
        list.map(
          from_array(branches),
          fn(branch) {
            let [
              #("node", _),
              #("name", name),
              #("pattern", pattern),
              #("then", then),
            ] = entries(branch)
            #(assert_string(name), pattern_from_json(pattern), from_json(then))
          },
        )
      ast.case_(value, branches)
    }
    "Hole" -> {
      let [] = rest
      ast.hole()
    }
    "Provider" -> {
      let [#("config", config), #("generator", generator)] = rest
      let config = assert_string(config)
      let generator = assert_string(generator)
      ast.provider(config, e.generator_from_string(generator))
    }
  }
}

fn pattern_from_json(json: JSON) {
  assert Ok(#(node, rest)) = list.key_pop(entries(json), "node")
  case assert_string(node) {
    "Variable" -> {
      let [#("label", label)] = rest
      p.Variable(assert_string(label))
    }
    "Tuple" -> {
      let [#("elements", elements)] = rest
      let elements =
        list.map(
          from_array(elements),
          fn(e) {
            assert Ok(#(node, rest)) = list.key_pop(entries(e), "node")
            case assert_string(node) {
              "Bind" -> {
                let [#("label", label)] = rest
                assert_string(label)
              }
            }
          },
        )
      p.Tuple(elements)
    }
    "Record" -> {
      let [#("fields", fields)] = rest
      let fields =
        list.map(
          from_array(fields),
          fn(f) {
            assert [#("key", key), #("bind", bind)] = entries(f)
            #(assert_string(key), assert_string(bind))
          },
        )
      p.Record(fields)
    }
  }
}
