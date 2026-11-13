//// Freeze a DOM clone and render it through SVG foreignObject into a PNG.

import gleam/float
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import plinthx/browser/canvas
import plinthx/browser/node as dom

fn attr(node, name) {
  dom.attribute(node, name) |> result.unwrap("")
}

fn checked(original, copy, property, attribute) {
  case dom.flag(original, property) {
    True -> dom.set_attribute(copy, attribute, "")
    False -> dom.remove_attribute(copy, attribute)
  }
}

fn freeze(pair) {
  let #(original, copy) = pair
  case dom.text(original, "tagName") {
    "CANVAS" ->
      case canvas.to_data_url(original) {
        Ok(url) -> {
          let image = dom.create("img")
          dom.set_attribute(image, "src", url)
          dom.set_attribute(image, "style", attr(original, "style"))
          dom.set_number(image, "width", dom.number(original, "width"))
          dom.set_number(image, "height", dom.number(original, "height"))
          dom.set_text(image, "className", dom.text(original, "className"))
          dom.replace(copy, image)
        }
        Error(_) -> Nil
      }
    "INPUT" ->
      case attr(original, "type") {
        "checkbox" | "radio" -> checked(original, copy, "checked", "checked")
        _ ->
          dom.set_attribute(
            copy,
            "value",
            dom.value(original) |> result.unwrap(""),
          )
      }
    "TEXTAREA" ->
      dom.set_text(
        copy,
        "textContent",
        dom.value(original) |> result.unwrap(""),
      )
    "OPTION" -> checked(original, copy, "selected", "selected")
    "SCRIPT" -> dom.remove(copy)
    "STYLE" ->
      dom.set_text(
        copy,
        "textContent",
        dom.text(original, "textContent") |> string.replace(":root", "html"),
      )
    _ -> Nil
  }
}

pub fn take(element: Option(dom.Node)) {
  use _ <- promise.await(dom.fonts_ready())
  use _ <- promise.await(dom.frame())
  let root = dom.root()
  let width = dom.number(root, "clientWidth")
  let height =
    float.max(
      dom.number(root, "scrollHeight"),
      dom.window_number("innerHeight"),
    )
  let clone = dom.clone(root)
  let originals = dom.query(root, "*") |> result.unwrap([])
  let copies = dom.query(clone, "*") |> result.unwrap([])
  list.each(list.zip(originals, copies), freeze)
  let style = dom.create("style")
  dom.set_text(
    style,
    "textContent",
    "*,*::before,*::after{animation-duration:0s!important;animation-delay:0s!important;animation-iteration-count:1!important;animation-fill-mode:both!important;transition:none!important;caret-color:transparent!important}",
  )
  case
    dom.query(clone, "head")
    |> result.try(fn(nodes) {
      list.first(nodes) |> result.replace_error("No matching element")
    })
  {
    Ok(head) -> dom.append(head, style)
    Error(_) -> Nil
  }
  dom.style(clone, "width", float.to_string(width) <> "px")
  dom.style(clone, "height", float.to_string(height) <> "px")
  let svg =
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\""
    <> float.to_string(width)
    <> "\" height=\""
    <> float.to_string(height)
    <> "\"><foreignObject x=\"0\" y=\"0\" width=\""
    <> float.to_string(width)
    <> "\" height=\""
    <> float.to_string(height)
    <> "\">"
    <> dom.serialize(clone)
    <> "</foreignObject></svg>"
  use decoded <- promise.await(canvas.image(
    "data:image/svg+xml;charset=utf-8," <> dom.encode_uri(svg),
  ))
  case decoded {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(image) -> {
      let #(left, top, width, height) = case element {
        Some(node) -> dom.rect(node)
        None -> #(
          0.0,
          0.0,
          dom.window_number("innerWidth"),
          dom.window_number("innerHeight"),
        )
      }
      let scale =
        float.min(float.max(dom.window_number("devicePixelRatio"), 1.0), 2.0)
      let canvas = dom.create("canvas")
      let dw = float.max(1.0, int.to_float(float.round(width *. scale)))
      let dh = float.max(1.0, int.to_float(float.round(height *. scale)))
      dom.set_number(canvas, "width", dw)
      dom.set_number(canvas, "height", dh)
      let context = canvas.context(canvas)
      canvas.fill_style(context, "#ffffff")
      canvas.fill_rect(context, 0.0, 0.0, dw, dh)
      canvas.draw_image(
        context,
        image,
        left +. dom.window_number("scrollX"),
        top +. dom.window_number("scrollY"),
        width,
        height,
        0.0,
        0.0,
        dw,
        dh,
      )
      flash()
      canvas.encode_png(canvas)
    }
  }
}

fn flash() {
  let flash = dom.create("div")
  dom.set_attribute(flash, "aria-hidden", "true")
  dom.set_attribute(
    flash,
    "style",
    "all:initial;position:fixed;inset:0;z-index:2147483647;pointer-events:none;background:#fff;opacity:0.65;transition:opacity 0.6s ease 0.25s",
  )
  dom.append(dom.root(), flash)
  let _ =
    promise.await(dom.frame(), fn(_) {
      use _ <- promise.map(dom.frame())
      dom.style(flash, "opacity", "0")
    })
  let _ = promise.map(dom.sleep(1200), fn(_) { dom.remove(flash) })
  Nil
}
