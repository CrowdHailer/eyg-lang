import lustre/attribute as a
import lustre/element/html as h

// build utils
pub fn css(source) {
  let #(path, _) = source
  h.link([a.rel("stylesheet"), a.href(path)])
  //    <link rel="stylesheet" href="style.css">
}

pub fn js(source) {
  let #(path, _) = source
  h.script([a.src(path)], "")
}

pub const layout_path = "/assets/layout.css"

pub fn layout_css() {
  h.link([a.rel("stylesheet"), a.href(layout_path)])
}

pub fn plausible(domain) {
  h.script(
    [
      a.attribute("defer", ""),
      a.attribute("data-domain", domain),
      a.src("https://plausible.io/js/script.js"),
    ],
    "",
  )
}

pub fn tailwind() {
  h.link([
    a.rel("stylesheet"),
    a.href("https://unpkg.com/tailwindcss@2.2.11/dist/tailwind.min.css"),
  ])
}
