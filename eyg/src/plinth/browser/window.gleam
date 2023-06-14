import gleam/javascript/promise.{Promise}

pub external fn alert(String) -> Nil =
  "" "alert"

pub external fn add_event_listener(String, fn(Nil) -> Nil) -> Nil =
  "" "addEventListener"

pub external fn encode_uri(String) -> String =
  "" "encodeURI"

pub external fn decode_uri(String) -> String =
  "" "decodeURI"

// files
pub external type FileHandle

// chrome only
// firefox support is for originprivatefilesystem and drag and drop blobs
// show dir for db of stuff only

pub external fn show_open_file_picker() -> Promise(Result(#(FileHandle), Nil)) =
  "../../plinth_ffi.js" "showOpenFilePicker"

pub external type File

pub external fn get_file(FileHandle) -> Promise(File) =
  "../../plinth_ffi.js" "getFile"

pub external fn file_text(File) -> Promise(String) =
  "../../plinth_ffi.js" "fileText"

// selection and ranges

pub external type Selection

pub external fn get_selection() -> Result(Selection, Nil) =
  "../../plinth_ffi.js" "getSelection"

pub external type Range

pub external fn get_range_at(Selection, Int) -> Result(Range, Nil) =
  "../../plinth_ffi.js" "getRangeAt"
