// publish an edition to the archive
// issue or publish an issue or version or revision
// to the library or archive
// library is poor name for the individual project
// project has releases/editions
// pub fn create_project() -> Nil {
//   todo
// }
// 
// Not called issue because sometimes a verb
// not called revision because what about the first
import eygir/expression
import gleam/dict.{type Dict}
import gleam/list
import gleam/result

pub type Edition {
  Edition(code: expression.Expression)
}

// A poject might apply to a package
pub type Package {
  Package(editions: List(Edition))
}

// separate archive from registry
// aliases: Dict(String, String), 
pub type Archive {
  Archive(packages: Dict(String, Package))
}

pub fn empty() {
  Archive(dict.new())
}

// TODO make an archive/client for pulling
// archive client is used by workspace/sync

// single registry actor where name and rename
// id is a uuid or hash of publisher id and timestamp
fn get_package(archive, id) {
  let Archive(packages:) = archive
  dict.get(packages, id)
}

fn set_package(archive, id, value) {
  let Archive(packages:) = archive
  Archive(dict.insert(packages, id, value))
}

fn check_access() {
  Ok(Nil)
}

fn check_version(editions, edition_number) {
  Ok(Nil)
}

fn check_code() {
  // type checks
  // doesn't reference workspace root or self
  // isn't missing any code
  // should both show up in type checking
  Ok(Nil)
}

// id based on flatpack 
pub fn publish(archive, package_id, edition_number, code, publisher) {
  case get_package(archive, package_id) {
    Ok(Package(editions)) -> {
      // TODO check access
      use Nil <- result.try(check_access())
      use Nil <- result.try(check_version(editions, edition_number))
      use Nil <- result.try(check_code())

      let editions = list.append(editions, [Edition(code)])
      todo
    }
    Error(Nil) ->
      case edition_number {
        0 -> {
          Ok(set_package(archive, package_id, Package([Edition(code)])))
          // TODO create package id
        }
        _ -> todo as "not new project"
      }
  }
}
