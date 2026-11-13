import hashi/app
import lustre

/// Start the page. The library and the syntax guide are passed in as text,
/// the page bundles both files rather than fetching them.
pub fn main(library: String, guide: String, seed: Int, origin: String) -> Nil {
  let app = lustre.application(app.init, app.update, app.view)
  let flags = app.Flags(library:, guide:, seed:, origin:)
  let assert Ok(_) = lustre.start(app, "#app", flags)
  Nil
}
