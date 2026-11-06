//// Evaluate shell input against a scope and a file system root.
////
//// Evaluation is pure apart from the block store, which only grows.
//// Effects are handled synchronously; file system effects move the root.
//// A failed command keeps the scope and root it started with.

import cloud/fs
import cloud/store.{type Store}
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/tree as ir
import eyg/parser
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import morph/editable as e
import multiformats/cid/v1.{type Cid}
import touch_grass/cryptography/hash
import touch_grass/decode_json
import touch_grass/eyg_parse
import touch_grass/file_system/append_file
import touch_grass/file_system/cwd
import touch_grass/file_system/delete_file
import touch_grass/file_system/make_directory
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file
import touch_grass/flip
import touch_grass/harness/computer
import touch_grass/interface
import touch_grass/now
import touch_grass/random
import touch_grass/sleep
import touch_grass/standard_error
import touch_grass/standard_in
import touch_grass/standard_out

/// Nodes are annotated with their path in the edited tree.
pub type Path =
  List(Int)

pub type Scope =
  state.Scope(Path)

pub type Value =
  state.Value(Path)

/// Everything a command can change.
pub type Snapshot {
  Snapshot(scope: Scope, root: Cid)
}

/// A piece of output, kept apart so the terminal can style each kind.
pub type Output {
  Stdout(String)
  Stderr(String)
  Result(String)
  Failure(String)
  /// A suggestion following a failure.
  Hint(String)
}

pub fn start(store: Store) -> Snapshot {
  Snapshot(scope: [], root: fs.empty(store))
}

/// Labels of the effects this shell handles.
pub const effects = [
  "ReadFile", "WriteFile", "AppendFile", "DeleteFile", "MakeDirectory",
  "ReadDirectory", "Cwd", "StandardOut", "StandardError", "Now", "Random",
  "Flip", "Sleep", "Hash", "DecodeJson", "EygParse", "StandardIn",
]

/// Read EYG source, such as pasted text, into an editable tree.
/// Assignments without a final expression are allowed.
pub fn parse(code: String) -> Result(e.Expression, String) {
  case parser.block_from_string(code) {
    Error(reason) -> Error(parser.format_error(reason, code))
    Ok(#(#(assignments, tail), _)) -> {
      let tail = option.unwrap(tail, #(ir.Vacant, #(0, 0)))
      // The parser gives the assignments last first.
      list.fold(assignments, tail, fn(acc, assignment) {
        let #(label, value, at) = assignment
        #(ir.Let(label, value, acc), at)
      })
      |> e.from_annotated
      |> e.open_all
      |> Ok
    }
  }
}

/// Run a command. On failure the snapshot is returned unchanged.
pub fn run(
  store: Store,
  expression: e.Expression,
  snapshot: Snapshot,
) -> #(List(Output), Snapshot) {
  let source = e.to_annotated(expression, [])
  let result = block.execute(source, snapshot.scope)
  let #(result, root, output) = loop(store, result, snapshot.root, [])
  case result {
    Ok(#(value, scope)) -> {
      let output = case value {
        Some(value) -> [Result(simple_debug.inspect(value)), ..output]
        None -> output
      }
      #(list.reverse(output), Snapshot(scope:, root:))
    }
    Error(reason) -> #(
      list.reverse([
        Hint("hint: " <> simple_debug.hint(reason)),
        Failure("error: " <> simple_debug.describe(reason)),
        ..output
      ]),
      snapshot,
    )
  }
}

fn loop(store, result, root, output) {
  case result {
    Ok(return) -> #(Ok(return), root, output)
    Error(#(break.UnhandledEffect(label, lift), _meta, env, k) as debug) ->
      case interface.cast(computer.effects(), label, lift) {
        Ok(effect) ->
          case handle(store, effect, root) {
            Handled(value, root, emitted) ->
              loop(
                store,
                block.resume(value, env, k),
                root,
                list.append(emitted, output),
              )
            Unsupported -> #(Error(debug.0), root, output)
          }
        Error(reason) -> #(Error(reason), root, output)
      }
    Error(#(reason, _meta, _env, _k)) -> #(Error(reason), root, output)
  }
}

type Handled {
  Handled(value: Value, root: Cid, output: List(Output))
  Unsupported
}

fn handle(store, effect: computer.Effect, root) -> Handled {
  case effect {
    computer.StandardOut(text) ->
      Handled(standard_out.encode(Nil), root, [Stdout(text)])
    computer.StandardError(text) ->
      Handled(standard_error.encode(Nil), root, [Stderr(text)])
    computer.ReadFile(read_file.Input(path:, offset:, limit:)) -> {
      let result = case fs.read_file(store, root, path) {
        Ok(contents) -> Ok(slice(contents, offset, limit))
        Error(reason) -> Error(reason)
      }
      Handled(read_file.encode(result), root, [])
    }
    computer.WriteFile(write_file.Input(path:, contents:)) -> {
      let #(result, root) =
        move(fs.write_file(store, root, path, contents), root)
      Handled(write_file.encode(result), root, [])
    }
    computer.AppendFile(append_file.Input(path:, contents:)) -> {
      let #(result, root) =
        move(fs.append_file(store, root, path, contents), root)
      Handled(append_file.encode(result), root, [])
    }
    computer.DeleteFile(path) -> {
      let #(result, root) = move(fs.delete_file(store, root, path), root)
      Handled(delete_file.encode(result), root, [])
    }
    computer.MakeDirectory(path) -> {
      let #(result, root) = move(fs.make_directory(store, root, path), root)
      Handled(make_directory.encode(result), root, [])
    }
    computer.ReadDirectory(path) -> {
      let result = case fs.read_directory(store, root, path) {
        Ok(entries) ->
          Ok(
            list.map(entries, fn(entry) {
              case entry {
                #(name, fs.Directory) -> #(name, read_directory.Directory)
                #(name, fs.File(size)) -> #(name, read_directory.File(size))
              }
            }),
          )
        Error(reason) -> Error(reason)
      }
      Handled(read_directory.encode(result), root, [])
    }
    computer.Cwd -> Handled(cwd.encode(Ok("/")), root, [])
    computer.Now -> Handled(now.encode(now.sync()), root, [])
    computer.Random(max) -> Handled(random.encode(random.sync(max)), root, [])
    computer.Flip -> Handled(flip.encode(flip.sync()), root, [])
    computer.Sleep(milliseconds) -> {
      process.sleep(int.clamp(milliseconds, 0, 10_000))
      Handled(sleep.encode(Nil), root, [])
    }
    computer.Hash(hash.Input(algorithm: hash.Sha256, bytes:)) ->
      Handled(hash.encode(crypto.hash(crypto.Sha256, bytes)), root, [])
    computer.DecodeJson(raw) -> Handled(decode_json.sync(raw), root, [])
    computer.EygParse(source) -> {
      let result = case parser.all_from_string(source) {
        Ok(node) -> Ok(node)
        Error(reason) -> Error(parser.format_error(reason, source))
      }
      Handled(eyg_parse.encode(result), root, [])
    }
    computer.StandardIn ->
      Handled(
        standard_in.encode(Error("standard in is not available in this shell")),
        root,
        [],
      )
    _ -> Unsupported
  }
}

/// Apply a file system change, keeping the old root when it fails.
fn move(result, root) {
  case result {
    Ok(root) -> #(Ok(Nil), root)
    Error(reason) -> #(Error(reason), root)
  }
}

fn slice(contents, offset, limit) {
  let size = bit_array.byte_size(contents)
  let offset = int.clamp(offset, 0, size)
  let length = int.clamp(limit, 0, size - offset)
  case bit_array.slice(contents, offset, length) {
    Ok(part) -> part
    Error(Nil) -> <<>>
  }
}
