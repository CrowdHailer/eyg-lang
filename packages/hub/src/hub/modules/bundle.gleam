import eyg/ir/car
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict
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

pub fn blocks(archive: Bundle(a)) -> List(#(v1.Cid, ir.Node(a))) {
  let Bundle(root:, dependencies:) = archive
  [root, ..dependencies]
}
