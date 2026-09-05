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
import midas/continuation
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
  use modules <- result.try(read_blocks(blocks, dict.new(), []))
  use root_module <- result.try(
    list.key_find(modules, root) |> result.replace_error(MissingRoot(root)),
  )
  let supplied = list.filter(modules, fn(module) { module.0 != root })
  strip(#(root, root_module), supplied)(fn(value) { value })
}

fn read_blocks(blocks, seen, acc) {
  case blocks {
    [] -> Ok(list.reverse(acc))
    [#(declared, bytes), ..rest] -> {
      use Nil <- result.try(case dict.has_key(seen, declared) {
        True -> Error(DuplicateCid(declared))
        False -> Ok(Nil)
      })
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
      read_blocks(rest, dict.insert(seen, declared, Nil), [
        #(declared, source),
        ..acc
      ])
    }
  }
}

fn strip(root, supplied) {
  let #(root_cid, source) = root
  use stripped <- continuation.then(
    strip_source(source, supplied, [], [root_cid]),
  )
  continuation.return(
    result.map(stripped, fn(dependencies) { Bundle(root:, dependencies:) }),
  )
}

fn strip_source(source, supplied, acc, visiting) {
  ir.fold(source, Ok(acc), fn(stripped, node) {
    case stripped {
      Error(reason) -> continuation.return(Error(reason))
      Ok(acc) -> {
        let #(expression, _meta) = node
        case expression {
          ir.Reference(reference) ->
            case reference_cid(reference) {
              Error(Nil) -> continuation.return(Ok(acc))
              Ok(cid) -> strip_reference(cid, supplied, acc, visiting)
            }
          _ -> continuation.return(Ok(acc))
        }
      }
    }
  })
}

fn strip_reference(cid, supplied, acc, visiting) {
  case cycle(visiting, cid) {
    Ok(cycle) -> continuation.return(Error(Circular(cycle)))
    Error(Nil) ->
      case list.key_find(acc, cid), list.key_find(supplied, cid) {
        Ok(_), _ -> continuation.return(Ok(acc))
        Error(Nil), Error(Nil) -> continuation.return(Ok(acc))
        Error(Nil), Ok(source) -> {
          use stripped <- continuation.then(
            strip_source(source, supplied, acc, [cid, ..visiting]),
          )
          continuation.return(
            result.map(stripped, fn(acc) { [#(cid, source), ..acc] }),
          )
        }
      }
  }
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
  resolve: fn(ir.Reference) -> Result(binding.Poly, ResolveError(resolve_error)),
) -> Result(Checked(meta), Rejection(meta, resolve_error)) {
  let Bundle(root: #(root, source), dependencies:) = archive
  use known <- result.try(check_dependencies(dependencies, dict.new(), resolve))
  use analysis <- result.try(check_module(
    infer.check(context, source),
    root,
    known,
    resolve,
  ))
  let types = dict.insert(known, root, infer.poly_type(analysis))
  Ok(Checked(analysis:, types:))
}

fn check_dependencies(dependencies, known, resolve) {
  case dependencies {
    [] -> Ok(known)
    [#(cid, source), ..rest] -> {
      use known <- result.try(check_dependencies(rest, known, resolve))
      use analysis <- result.try(check_module(
        infer.check(infer.pure(), source),
        cid,
        known,
        resolve,
      ))
      Ok(dict.insert(known, cid, infer.poly_type(analysis)))
    }
  }
}

fn check_module(step, module, known, resolve) {
  case step {
    infer.Done(analysis) ->
      case infer.all_errors(analysis) {
        [] -> Ok(analysis)
        errors -> Error(Unsound(module, errors))
      }
    infer.Lookup(reference:, resume:) ->
      case held(known, reference) {
        Ok(type_) -> check_module(resume(Ok(type_)), module, known, resolve)
        Error(Nil) ->
          case resolve(reference) {
            Ok(type_) -> check_module(resume(Ok(type_)), module, known, resolve)
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
