import gleam/result.{try}
import gleam/javascript/promise
import plinth/javascript/console
import plinth/browser/file_system
import eyg/runtime/cast
import eyg/runtime/value as v

pub fn file_read(name) {
  use name <- try(cast.as_string(name))
  let p =
    promise.await(file_system.show_directory_picker(), fn(dir_handle) {
      console.log(dir_handle)
      case dir_handle {
        Ok(dir_handle) -> {
          promise.map(
            file_system.get_file_handle(dir_handle, name),
            console.log,
          )
          promise.map(file_system.all_entries(dir_handle), console.log)
        }
        Error(x) -> panic as x
      }
      promise.resolve(v.unit)
    })
  Ok(v.Promise(p))
}
