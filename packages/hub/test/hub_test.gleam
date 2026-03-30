import gleeunit
import hub/helpers

pub fn main() -> Nil {
  let Nil = helpers.start_db()
  gleeunit.main()
}
