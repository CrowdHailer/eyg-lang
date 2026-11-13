import lustre
import todomvc/app

/// Start the page. The library and the syntax guide are passed in as text,
/// the page bundles both files rather than fetching them.
pub fn main(library: String, guide: String, origin: String) -> Nil {
  let app = lustre.application(app.init, app.update, app.view)
  let assert Ok(_) =
    lustre.start(app, "#app", app.Flags(library:, guide:, origin:))
  Nil
}
