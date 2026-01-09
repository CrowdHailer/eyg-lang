import lustre/attribute as a
import lustre/element/html as h
import website/routes/sign/view

pub fn render() {
  [
    h.div(
      [
        a.styles([
          #("display", "grid"),
          #("grid-template-columns", "repeat(auto-fill, minmax(400px,500px))"),
          #("gap", "20px"),
          #("justify-content", "center"),
          #("padding", "20px"),
          #("background", "#e3f5ef"),
        ]),
      ],
      [
        card([view.render(view.Confirm)]),
        card([view.render(view.Setup)]),
        // Link via QR code
        card([view.render(view.Link)]),
        // Confirm link
        card([view.render(view.Choose([]))]),
        // Add to the account
        card([view.render(view.Loading)]),
        card([view.render(view.Loading)]),
        card([view.render(view.Loading)]),
        card([view.render(view.Loading)]),
      ],
    ),
  ]
}

fn card(contents) {
  h.div(
    [
      a.styles([
        #("height", "600px"),
        #("background", "#fff"),
      ]),
    ],
    contents,
  )
}
