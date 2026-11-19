import cloud/helpers
import gleeunit

pub fn main() -> Nil {
  let Nil = helpers.start_db()
  gleeunit.main()
}
