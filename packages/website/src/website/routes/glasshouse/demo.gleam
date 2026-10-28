//// The demo traces, read when the site is built to show real output on the static pages.

import glasshouse/archive.{type Archive}
import glasshouse/cohort
import gleam/json
import simplifile

pub const directory = "src/website/routes/glasshouse/demo/"

/// A demo archive by its slug, i.e. `session` or `with-totals`.
pub fn archive(slug: String) -> Archive {
  let assert Ok(text) = simplifile.read(directory <> slug <> ".json")
  let assert Ok(archive) = archive.from_string(text)
  archive
}

/// The cohort report `eyg evaluate` saved for the demo variants.
pub fn report() -> List(cohort.Summary) {
  let assert Ok(text) = simplifile.read(directory <> "cohort.json")
  let assert Ok(#(_, summaries)) = json.parse(text, cohort.report_decoder())
  summaries
}
