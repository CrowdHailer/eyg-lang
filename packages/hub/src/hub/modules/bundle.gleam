import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/ir/car
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/result
import hub/cid
import multiformats/cid/v1

/// A root module and its reachable dependencies.
/// Dependencies are ordered with dependants before their dependencies.
pub type Bundle(meta) {
  Bundle(
    root: #(v1.Cid, ir.Node(meta)),
    dependencies: List(#(v1.Cid, ir.Node(meta))),
  )
}

pub type ShakeError {
  InvalidCar(String)
  UnsupportedVersion(Int)
  InvalidRootCount(Int)
  IncorrectCid(declared: v1.Cid, actual: v1.Cid)
  DuplicateCid(v1.Cid)
  InvalidModule(v1.Cid)
  MissingRoot(v1.Cid)
  Circular(List(v1.Cid))
}

pub type Checked(meta) {
  Checked(analysis: infer.Analysis(meta), types: Dict(v1.Cid, binding.Poly))
}

pub type ResolveError(error) {
  NotFound
  Failed(error)
}

pub type Rejection(meta, resolve_error) {
  Unsound(module: v1.Cid, errors: List(#(meta, error.Reason)))
  Missing(module: v1.Cid, reference: ir.Reference)
  ResolutionFailed(resolve_error)
}

/// Decode an uploaded CAR and retain only modules reachable from its root.
pub fn shake(upload: BitArray) -> Result(Bundle(Nil), ShakeError) {
  use archive <- result.try(car.decode(upload) |> result.map_error(InvalidCar))
  let car.Car(header: car.Header(version:, roots:), blocks:) = archive
  use Nil <- result.try(case version {
    1 -> Ok(Nil)
    version -> Error(UnsupportedVersion(version))
  })
  use root <- result.try(case roots {
    [root] -> Ok(root)
    roots -> Error(InvalidRootCount(list.length(roots)))
  })
  use supplied <- result.try(index_blocks(blocks, dict.new()))
  use Nil <- result.try(case dict.has_key(supplied, root) {
    True -> Ok(Nil)
    False -> Error(MissingRoot(root))
  })
  use #(_, modules) <- result.try(
    read_reachable(root, supplied, dict.new(), [], []),
  )
  let assert [root, ..dependencies] = modules
  Ok(Bundle(root:, dependencies:))
}

fn index_blocks(blocks, indexed) {
  case blocks {
    [] -> Ok(indexed)
    [#(declared, bytes), ..rest] -> {
      use Nil <- result.try(case dict.has_key(indexed, declared) {
        True -> Error(DuplicateCid(declared))
        False -> Ok(Nil)
      })
      index_blocks(rest, dict.insert(indexed, declared, bytes))
    }
  }
}

fn read_reachable(cid, supplied, seen, visiting, acc) {
  case dict.has_key(seen, cid) {
    True -> Ok(#(seen, acc))
    False -> {
      use Nil <- result.try(case cycle(visiting, cid) {
        Ok(cycle) -> Error(Circular(cycle))
        Error(Nil) -> Ok(Nil)
      })
      let assert Ok(bytes) = dict.get(supplied, cid)
      use source <- result.try(read_module(cid, bytes))
      let references =
        ir.list_references(source)
        |> list.filter_map(reference_cid)
      use #(seen, acc) <- result.try(read_references(
        references,
        supplied,
        seen,
        [cid, ..visiting],
        acc,
      ))
      Ok(#(dict.insert(seen, cid, Nil), [#(cid, source), ..acc]))
    }
  }
}

fn read_references(references, supplied, seen, visiting, acc) {
  case references {
    [] -> Ok(#(seen, acc))
    [cid, ..rest] -> {
      use #(seen, acc) <- result.try(case dict.has_key(supplied, cid) {
        True -> read_reachable(cid, supplied, seen, visiting, acc)
        False -> Ok(#(seen, acc))
      })
      read_references(rest, supplied, seen, visiting, acc)
    }
  }
}

fn read_module(declared, bytes) {
  use Nil <- result.try(case cid.from_block(bytes) {
    actual if actual == declared -> Ok(Nil)
    actual -> Error(IncorrectCid(declared, actual))
  })
  use source <- result.try(
    json.parse_bits(bytes, dag_json.decoder(Nil))
    |> result.replace_error(InvalidModule(declared)),
  )
  use Nil <- result.try(case cid.from_tree(source) {
    actual if actual == declared -> Ok(Nil)
    actual -> Error(IncorrectCid(declared, actual))
  })
  Ok(source)
}

fn cycle(visiting, cid) {
  let #(before, cycle) = list.split_while(visiting, fn(item) { item != cid })
  case cycle {
    [] -> Error(Nil)
    _ -> Ok([cid, ..list.reverse(before)] |> list.append([cid]))
  }
}

fn reference_cid(reference) {
  case reference {
    ir.Content(cid:) | ir.Pinned(ir.Release(module: cid, ..)) -> Ok(cid)
    _ -> Error(Nil)
  }
}

/// Check dependencies as pure modules, then check the root with `context`.
/// The resolver supplies types for dependencies omitted by `shake`.
pub fn check(
  archive: Bundle(meta),
  context: infer.Context,
  state: state,
  resolve: fn(ir.Reference, state) ->
    Result(#(binding.Poly, state), ResolveError(resolve_error)),
) -> Result(#(Checked(meta), state), Rejection(meta, resolve_error)) {
  let Bundle(root: #(root, source), dependencies:) = archive
  use #(known, state) <- result.try(check_dependencies(
    dependencies,
    dict.new(),
    state,
    resolve,
  ))
  use #(analysis, state) <- result.try(check_module(
    infer.check(context, source),
    root,
    known,
    state,
    resolve,
  ))
  let types = dict.insert(known, root, infer.poly_type(analysis))
  Ok(#(Checked(analysis:, types:), state))
}

fn check_dependencies(dependencies, known, state, resolve) {
  case dependencies {
    [] -> Ok(#(known, state))
    [#(cid, source), ..rest] -> {
      use #(known, state) <- result.try(check_dependencies(
        rest,
        known,
        state,
        resolve,
      ))
      use #(analysis, state) <- result.try(check_module(
        infer.check(infer.pure(), source),
        cid,
        known,
        state,
        resolve,
      ))
      Ok(#(dict.insert(known, cid, infer.poly_type(analysis)), state))
    }
  }
}

fn check_module(step, module, known, state, resolve) {
  case step {
    infer.Done(analysis) ->
      case infer.all_errors(analysis) {
        [] -> Ok(#(analysis, state))
        errors -> Error(Unsound(module, errors))
      }
    infer.Lookup(reference:, resume:) ->
      case held(known, reference) {
        Ok(type_) ->
          check_module(resume(Ok(type_)), module, known, state, resolve)
        Error(Nil) ->
          case resolve(reference, state) {
            Ok(#(type_, state)) ->
              check_module(resume(Ok(type_)), module, known, state, resolve)
            Error(NotFound) -> Error(Missing(module, reference))
            Error(Failed(reason)) -> Error(ResolutionFailed(reason))
          }
      }
  }
}

fn held(known, reference) {
  case reference {
    ir.Content(cid:) -> dict.get(known, cid)
    _ -> Error(Nil)
  }
}

pub fn blocks(archive: Bundle(a)) -> List(#(v1.Cid, ir.Node(a))) {
  let Bundle(root:, dependencies:) = archive
  [root, ..dependencies]
}
