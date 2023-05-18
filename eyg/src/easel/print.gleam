import eygir/expression as e

pub fn print(source) {
  case source {
    e.Lambda(param, body) -> param
    _ -> ""
  }
}
