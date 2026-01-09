import plinth/browser/file_system
import spotless/origin
import website/config

pub fn config() {
  config.Config(origin: origin.https("eyg.test"))
}

@external(javascript, "../../website_ffi.mjs", "any")
fn any() -> a

pub fn dummy_directory_handle() -> file_system.DirectoryHandle {
  any()
}
