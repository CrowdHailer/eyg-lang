import gleam/javascript/promise.{Promise}

pub external fn alert(String) -> Nil =
  "" "alert"

pub external fn add_event_listener(String, fn(Nil) -> Nil) -> Nil =
  "" "addEventListener"

pub external fn encode_uri(String) -> String =
  "" "encodeURI"

pub external fn decode_uri(String) -> String =
  "" "decodeURI"

pub external type FileHandle

pub external fn show_open_file_picker() -> Promise(#(FileHandle)) =
  "" "showOpenFilePicker"

pub external type File

pub external fn get_file(FileHandle) -> Promise(File) =
  "../../plinth_ffi.js" "getFile"

pub external fn file_text(File) -> Promise(String) =
  "../../plinth_ffi.js" "fileText"
