import plinth/browser/crypto/subtle
import plinth/browser/file_system
import plinth/browser/indexeddb/database
import plinth/browser/window_proxy
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

pub fn dummy_opener() -> window_proxy.WindowProxy {
  any()
}

pub fn dummy_db() -> database.Database {
  any()
}

pub fn dummy_crypto_key() -> subtle.CryptoKey {
  any()
}
