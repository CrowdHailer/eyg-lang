import lustre/attribute as a
import lustre/element/html as h

// build utils
pub fn css(source) {
  let #(path, _) = source
  h.link([a.rel("stylesheet"), a.href(path)])
  //    <link rel="stylesheet" href="style.css">
}
