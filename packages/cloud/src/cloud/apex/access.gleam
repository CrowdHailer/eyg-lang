//// Who may use the servers. There are no accounts yet.
////
//// Without a password the API and web interface only accept local connections.
//// With `ACCESS_PASSWORD` set they accept connections on every interface,
//// and every request must give the password with HTTP basic authentication, with any user name.

import gleam/bit_array
import gleam/crypto
import gleam/string

pub type Access {
  Local
  Password(String)
}

/// The address servers listen on.
pub fn bind(access: Access) -> String {
  case access {
    Local -> "127.0.0.1"
    Password(_) -> "0.0.0.0"
  }
}

/// Whether the value of a request's authorization header lets it in.
pub fn allowed(access: Access, authorization: Result(String, Nil)) -> Bool {
  case access, authorization {
    Local, _ -> True
    Password(password), Ok("Basic " <> encoded) ->
      case bit_array.base64_decode(encoded) {
        Ok(decoded) ->
          case bit_array.to_string(decoded) {
            Ok(credentials) ->
              case string.split_once(credentials, ":") {
                Ok(#(_, given)) ->
                  crypto.secure_compare(<<given:utf8>>, <<password:utf8>>)
                Error(Nil) -> False
              }
            Error(Nil) -> False
          }
        Error(Nil) -> False
      }
    Password(_), _ -> False
  }
}

/// The header that asks a browser for the password.
pub const challenge = #("www-authenticate", "Basic realm=\"EYG cloud\"")
