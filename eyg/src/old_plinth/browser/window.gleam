import gleam/option.{Option}
import gleam/javascript/array.{Array}
import gleam/javascript/promise.{Promise}

@external(javascript, "../../plinth_ffi.js", "alert")
pub fn alert(a: String) -> Nil

@external(javascript, "../../plinth_ffi.js", "addEventListener")
pub fn add_event_listener(a: String, b: fn(Nil) -> Nil) -> Nil

@external(javascript, "../../plinth_ffi.js", "encodeURI")
pub fn encode_uri(a: String) -> String

@external(javascript, "../../plinth_ffi.js", "decodeURI")
pub fn decode_uri(a: String) -> String

@external(javascript, "../../plinth_ffi.js", "decodeURIComponent")
pub fn decode_uri_component(a: String) -> String

// Not sure it's worth returning location as a Gleam URL because all  components are optional
// however page must have an origin/protocol but it might be file based.
// Nice having a simple location effect in eyg

@external(javascript, "../../plinth_ffi.js", "locationSearch")
pub fn location_search() -> Result(String, Nil)

// files
pub type FileHandle

// chrome only
// firefox support is for originprivatefilesystem and drag and drop blobs
// show dir for db of stuff only

// single tuple is hack for list of files
@external(javascript, "../../plinth_ffi.js", "showOpenFilePicker")
pub fn show_open_file_picker() -> Promise(Result(#(FileHandle), Nil))

@external(javascript, "../../plinth_ffi.js", "showSaveFilePicker")
pub fn show_save_file_picker() -> Promise(Result(FileHandle, Nil))

pub type File

@external(javascript, "../../plinth_ffi.js", "getFile")
pub fn get_file(a: FileHandle) -> Promise(File)

@external(javascript, "../../plinth_ffi.js", "fileText")
pub fn file_text(a: File) -> Promise(String)

pub type FileSystemWritableFileStream

@external(javascript, "../../plinth_ffi.js", "createWritable")
pub fn create_writable(a: FileHandle) -> Promise(FileSystemWritableFileStream)

pub type Blob

@external(javascript, "../../plinth_ffi.js", "blob")
pub fn blob(a: Array(String), b: String) -> Blob

@external(javascript, "../../plinth_ffi.js", "write")
pub fn write(a: FileSystemWritableFileStream, b: Blob) -> Promise(Nil)

@external(javascript, "../../plinth_ffi.js", "close")
pub fn close(a: FileSystemWritableFileStream) -> Promise(Nil)

// selection and ranges

pub type Selection

@external(javascript, "../../plinth_ffi.js", "getSelection")
pub fn get_selection() -> Result(Selection, Nil)

pub type Range

@external(javascript, "../../plinth_ffi.js", "getRangeAt")
pub fn get_range_at(a: Selection, b: Int) -> Result(Range, Nil)
