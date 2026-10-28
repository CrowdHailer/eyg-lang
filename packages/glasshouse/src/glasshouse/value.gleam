//// Canonical EYG expressions for runtime values.
////
//// A recorded effect input or reply is stored as the EYG expression that evaluates to it.
//// Record fields are sorted by label so equal values encode to equal expressions.
//// Large binaries can be moved into the store and replaced by a content reference,
//// decoding resolves those references from the store.

import eyg/interpreter/break
import eyg/interpreter/capture
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/dag_json as ir_json
import eyg/ir/tree as ir
import glasshouse/store.{type Sha256, type Store}
import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import multiformats/cid/v1

/// An expression that evaluates to a recorded value.
pub type Encoded =
  ir.Node(Nil)

/// The canonical expression for a value.
///
/// Closures are captured with the variables they use.
/// A continuation, `resume` from a handler, has no expression and encodes as vacant.
pub fn encode(value: v.Value(m, c)) -> Encoded {
  case value {
    v.Binary(bytes) -> #(ir.Binary(bytes), Nil)
    v.Integer(i) -> #(ir.Integer(i), Nil)
    v.String(s) -> #(ir.String(s), Nil)
    v.LinkedList(items) ->
      list.fold_right(items, #(ir.Tail, Nil), fn(tail, item) {
        apply(apply(#(ir.Cons, Nil), encode(item)), tail)
      })
    v.Record(fields) ->
      dict.to_list(fields)
      |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
      |> list.fold_right(#(ir.Empty, Nil), fn(rest, field) {
        let #(label, item) = field
        apply(apply(#(ir.Extend(label), Nil), encode(item)), rest)
      })
    v.Tagged(label, inner) -> apply(#(ir.Tag(label), Nil), encode(inner))
    v.Closure(_, body, _) ->
      capture.capture(value, body.1)
      |> ir.map_annotation(fn(_) { Nil })
    v.Partial(switch, applied) ->
      list.fold(applied, #(partial(switch), Nil), fn(function, argument) {
        apply(function, encode(argument))
      })
  }
}

fn apply(function: Encoded, argument: Encoded) -> Encoded {
  #(ir.Apply(function, argument), Nil)
}

fn partial(switch: v.Switch(c)) -> ir.Expression(Nil) {
  case switch {
    v.Cons -> ir.Cons
    v.Extend(label) -> ir.Extend(label)
    v.Overwrite(label) -> ir.Overwrite(label)
    v.Select(label) -> ir.Select(label)
    v.Tag(label) -> ir.Tag(label)
    v.Match(label) -> ir.Case(label)
    v.NoCases -> ir.NoCases
    v.Perform(label) -> ir.Perform(label)
    v.Handle(label) -> ir.Handle(label)
    v.Mask(label) -> ir.Mask(label)
    v.Shallow(label) -> ir.Shallow(label)
    v.Pure -> ir.Builtin("pure")
    v.Builtin(identifier) -> ir.Builtin(identifier)
    v.Resume(_) -> ir.Vacant
  }
}

/// Evaluate an encoded value, resolving content references from the store.
/// Evaluation is pure, any effect is an error.
pub fn decode(
  encoded: Encoded,
  store: Store,
  meta: m,
) -> Result(state.Value(m), String) {
  let source = ir.map_annotation(encoded, fn(_) { meta })
  resolve(expression.execute(source, []), store, meta)
}

fn resolve(return, store, meta) {
  case return {
    Ok(value) -> Ok(value)
    Error(#(break.UndefinedReference(ir.Content(cid)), _, env, k)) -> {
      use node <- result.try(store.get_node(store, v1.to_string(cid)))
      use value <- result.try(decode(node, store, meta))
      resolve(expression.resume(value, env, k), store, meta)
    }
    Error(#(reason, _, _, _)) -> Error(simple_debug.describe(reason))
  }
}

/// Move binaries larger than `threshold` bytes into the store as `Binary` modules,
/// each is replaced with a reference to its CID.
pub fn externalize(
  encoded: Encoded,
  store: Store,
  threshold: Int,
  sha256: Sha256,
) -> #(Encoded, Store) {
  let #(exp, _) = encoded
  case exp {
    ir.Binary(bytes) ->
      case bit_array.byte_size(bytes) > threshold {
        True -> {
          let #(store, id) = store.put_binary(store, bytes, sha256)
          let assert Ok(#(cid, _)) = v1.from_string(id)
          #(#(ir.Reference(ir.Content(cid)), Nil), store)
        }
        False -> #(encoded, store)
      }
    ir.Apply(function, argument) -> {
      let #(function, store) = externalize(function, store, threshold, sha256)
      let #(argument, store) = externalize(argument, store, threshold, sha256)
      #(#(ir.Apply(function, argument), Nil), store)
    }
    ir.Lambda(label, body) -> {
      let #(body, store) = externalize(body, store, threshold, sha256)
      #(#(ir.Lambda(label, body), Nil), store)
    }
    ir.Let(label, definition, then) -> {
      let #(definition, store) =
        externalize(definition, store, threshold, sha256)
      let #(then, store) = externalize(then, store, threshold, sha256)
      #(#(ir.Let(label, definition, then), Nil), store)
    }
    _ -> #(encoded, store)
  }
}

/// Replace every content reference with the stored module, recursively.
pub fn inline(encoded: Encoded, store: Store) -> Result(Encoded, String) {
  let #(exp, _) = encoded
  case exp {
    ir.Reference(ir.Content(cid)) -> {
      use node <- result.try(store.get_node(store, v1.to_string(cid)))
      inline(node, store)
    }
    ir.Apply(function, argument) -> {
      use function <- result.try(inline(function, store))
      use argument <- result.try(inline(argument, store))
      Ok(#(ir.Apply(function, argument), Nil))
    }
    ir.Lambda(label, body) -> {
      use body <- result.try(inline(body, store))
      Ok(#(ir.Lambda(label, body), Nil))
    }
    ir.Let(label, definition, then) -> {
      use definition <- result.try(inline(definition, store))
      use then <- result.try(inline(then, store))
      Ok(#(ir.Let(label, definition, then), Nil))
    }
    _ -> Ok(encoded)
  }
}

/// Is a runtime value equal to a recorded value.
pub fn matches(value: v.Value(m, c), recorded: Encoded, store: Store) -> Bool {
  case inline(encode(value), store), inline(recorded, store) {
    Ok(actual), Ok(recorded) -> actual == recorded
    _, _ -> False
  }
}

/// CIDs of all stored modules a recorded value refers to.
pub fn references(encoded: Encoded) -> List(String) {
  do_references(encoded, [])
  |> list.unique
}

fn do_references(encoded: Encoded, acc) {
  let #(exp, _) = encoded
  case exp {
    ir.Reference(ir.Content(cid)) -> [v1.to_string(cid), ..acc]
    ir.Apply(function, argument) ->
      do_references(argument, do_references(function, acc))
    ir.Lambda(_, body) -> do_references(body, acc)
    ir.Let(_, definition, then) ->
      do_references(then, do_references(definition, acc))
    _ -> acc
  }
}

/// Render a recorded value in EYG syntax, references are resolved from the store.
pub fn render(encoded: Encoded, store: Store) -> String {
  case decode(encoded, store, Nil) {
    Ok(value) -> simple_debug.inspect(value)
    Error(reason) -> "<" <> reason <> ">"
  }
}

/// Render a recorded value for people, binaries are shown as a short excerpt of their text.
pub fn summary(encoded: Encoded, store: Store, limit: Int) -> String {
  case decode(encoded, store, Nil) {
    Ok(value) -> {
      let rendered = simple_debug.inspect(excerpts(value))
      case string.length(rendered) > limit {
        True -> string.slice(rendered, 0, limit) <> "…"
        False -> rendered
      }
    }
    Error(reason) -> "<" <> reason <> ">"
  }
}

fn excerpts(value: v.Value(m, c)) -> v.Value(m, c) {
  case value {
    v.Binary(bytes) -> {
      let size = bit_array.byte_size(bytes)
      let text = case bit_array.to_string(bytes) {
        Ok(text) ->
          case string.length(text) > 40 {
            True -> " " <> string.slice(text, 0, 40) <> "…"
            False -> " " <> text
          }
        Error(Nil) -> ""
      }
      v.String("<" <> int.to_string(size) <> " bytes>" <> text)
    }
    v.LinkedList(items) -> v.LinkedList(list.map(items, excerpts))
    v.Record(fields) ->
      v.Record(dict.map_values(fields, fn(_, f) { excerpts(f) }))
    v.Tagged(label, inner) -> v.Tagged(label, excerpts(inner))
    _ -> value
  }
}

/// The CID of a value without storing it,
/// identifies a request a policy changed without keeping its contents.
pub fn fingerprint(value: v.Value(m, c), sha256: Sha256) -> String {
  encode(value)
  |> ir_json.to_block
  |> store.cid(sha256)
  |> v1.to_string
}
