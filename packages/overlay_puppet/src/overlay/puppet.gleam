//// Preview driver. All locator, retry, action and screenshot orchestration is Gleam.

import gleam/float
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleam/string
import javascript/mutable_reference as ref
import overlay/puppet/locator
import overlay/puppet/protocol
import overlay/puppet/screenshot
import overlay/web/puppet as p
import plinthx/browser/node as dom

pub type Failure {
  Retry(String)
  Fatal(String)
}

pub fn main() {
  let seen = ref.new(set.new())
  let marker = ref.new(None)
  dom.on_message(fn(message) {
    case dom.from_parent(message), protocol.message(dom.message_data(message)) {
      True, Ok(#(id, request)) ->
        case set.contains(ref.get(seen), id) {
          True -> Nil
          False -> {
            ref.set(seen, set.insert(ref.get(seen), id))
            let _ =
              perform(request, marker)
              |> promise.rescue(fn(reason) { Error(string.inspect(reason)) })
              |> promise.map(fn(reply) {
                let reply = case reply {
                  Ok(value) -> value
                  Error(reason) -> protocol.failure(reason)
                }
                dom.post_to_host(
                  json.to_string(
                    json.object([#("id", json.string(id)), #("reply", reply)]),
                  ),
                )
                let _ =
                  promise.map(dom.sleep(60_000), fn(_) {
                    ref.set(seen, set.delete(ref.get(seen), id))
                  })
                Nil
              })
            Nil
          }
        }
      _, _ -> Nil
    }
  })
}

fn poll(deadline, timeout, check) {
  case check() {
    Ok(value) -> promise.resolve(Ok(value))
    Error(Fatal(reason)) -> promise.resolve(Error(reason))
    Error(Retry(reason)) ->
      case dom.now() >= deadline {
        True ->
          promise.resolve(Error(
            "Timeout " <> int.to_string(timeout) <> "ms: " <> reason,
          ))
        False -> {
          use _ <- promise.await(dom.sleep(50))
          poll(deadline, timeout, check)
        }
      }
  }
}

fn one(request: protocol.Request, interactive) {
  let check = fn() {
    use nodes <- result.try(
      locator.resolve(request.locator) |> result.map_error(Fatal),
    )
    let description = locator.describe(request.locator)
    case nodes {
      [] -> Error(Retry(description <> " matched no elements"))
      [node] ->
        case interactive, locator.visible(node), dom.flag(node, "disabled") {
          True, False, _ -> Error(Retry(description <> " is not visible"))
          True, _, True -> Error(Retry(description <> " is disabled"))
          _, _, _ -> Ok(node)
        }
      nodes ->
        Error(Fatal(
          description
          <> " matched "
          <> int.to_string(list.length(nodes))
          <> " elements. Use first, nth or a more specific locator",
        ))
    }
  }
  poll(dom.now() + request.timeout, request.timeout, check)
}

fn with_one(request, interactive, handle) {
  use selected <- promise.await(one(request, interactive))
  case selected {
    Ok(node) -> handle(node)
    Error(reason) -> promise.resolve(Error(reason))
  }
}

fn point(node, marker) {
  dom.scroll(node, "nearest")
  let box = case ref.get(marker) {
    Some(box) -> box
    None -> {
      let box = dom.create("div")
      dom.set_attribute(box, "aria-hidden", "true")
      dom.set_attribute(
        box,
        "style",
        "all:initial;position:fixed;z-index:2147483647;pointer-events:none;border:2px solid #6d5dfc;border-radius:8px;box-shadow:0 0 0 4px rgba(109,93,252,.25);transition:all .25s ease;opacity:0",
      )
      ref.set(marker, Some(box))
      box
    }
  }
  case dom.flag(box, "isConnected") {
    True -> Nil
    False -> dom.append(dom.root(), box)
  }
  let #(left, top, width, height) = dom.rect(node)
  list.each(
    [
      #("left", left -. 4.0),
      #("top", top -. 4.0),
      #("width", width +. 8.0),
      #("height", height +. 8.0),
    ],
    fn(pair) { dom.style(box, pair.0, float.to_string(pair.1) <> "px") },
  )
  dom.style(box, "opacity", "1")
  dom.sleep(260)
}

fn unpoint(marker) {
  case ref.get(marker) {
    Some(box) -> dom.style(box, "opacity", "0")
    None -> Nil
  }
}

fn pointers(node, events) {
  let #(left, top, width, height) = dom.rect(node)
  list.each(events, fn(event) {
    let constructor = case string.starts_with(event, "pointer") {
      True -> "PointerEvent"
      False -> "MouseEvent"
    }
    let _ =
      dom.pointer(
        node,
        constructor,
        event,
        left +. width /. 2.0,
        top +. height /. 2.0,
      )
    Nil
  })
}

fn set_value(node, value) {
  let owner = case dom.text(node, "tagName") {
    "TEXTAREA" -> "HTMLTextAreaElement"
    "SELECT" -> "HTMLSelectElement"
    _ -> "HTMLInputElement"
  }
  dom.set_inherited_value(node, owner, value)
  let _ = dom.event(node, "input")
  let _ = dom.event(node, "change")
  Nil
}

fn done() {
  promise.resolve(Ok(protocol.done()))
}

fn read(value) {
  promise.resolve(Ok(protocol.text(value)))
}

pub fn perform(request: protocol.Request, marker) {
  case request.action {
    p.Count ->
      promise.resolve(
        result.map(locator.resolve(request.locator), fn(nodes) {
          protocol.tagged("count", [#("value", json.int(list.length(nodes)))])
        }),
      )
    p.AllTextContents ->
      promise.resolve(
        result.map(locator.resolve(request.locator), fn(nodes) {
          protocol.tagged("texts", [
            #(
              "value",
              json.array(nodes, fn(node) {
                json.string(dom.text(node, "textContent"))
              }),
            ),
          ])
        }),
      )
    p.IsVisible ->
      promise.resolve(
        result.map(locator.resolve(request.locator), fn(nodes) {
          protocol.flag(list.any(list.take(nodes, 1), locator.visible))
        }),
      )
    p.Expect(condition) -> {
      use checked <- promise.map(
        poll(dom.now() + request.timeout, request.timeout, fn() {
          expect(request.locator, condition)
        }),
      )
      result.map(checked, fn(_) { protocol.done() })
    }
    p.Screenshot -> {
      case ref.get(marker) {
        Some(box) -> dom.remove(box)
        None -> Nil
      }
      case request.locator {
        [] -> capture(None)
        _ -> with_one(request, False, fn(node) { capture(Some(node)) })
      }
    }
    p.Press(key) -> {
      let selected = case request.locator {
        [] -> promise.resolve(Ok(dom.active() |> result.unwrap(dom.body())))
        _ -> one(request, True)
      }
      use selected <- promise.await(selected)
      case selected {
        Error(reason) -> promise.resolve(Error(reason))
        Ok(node) -> {
          use _ <- promise.await(point(node, marker))
          dom.focus(node)
          let proceed = dom.keyboard(node, "keydown", key)
          case
            proceed,
            dom.value(node),
            string.length(key) == 1,
            dom.text(node, "tagName") != "SELECT"
          {
            True, Ok(value), True, True -> set_value(node, value <> key)
            _, _, _, _ -> Nil
          }
          case proceed, key, dom.form(node) {
            True, "Enter", Ok(form) -> dom.submit(form)
            _, _, _ -> Nil
          }
          let _ = dom.keyboard(node, "keyup", key)
          unpoint(marker)
          done()
        }
      }
    }
    action -> {
      let interactive = case action {
        p.Click | p.Fill(_) | p.SetChecked(_) | p.SelectOption(_) | p.Hover ->
          True
        _ -> False
      }
      with_one(request, interactive, fn(node) { act(node, action, marker) })
    }
  }
}

fn capture(node) {
  use result <- promise.map(screenshot.take(node))
  result.map(result, fn(url) {
    protocol.tagged("image", [#("value", json.string(url))])
  })
}

fn act(node, action, marker) {
  case action {
    p.Click -> {
      use _ <- promise.await(point(node, marker))
      pointers(node, [
        "pointerover",
        "pointerenter",
        "mouseover",
        "pointerdown",
        "mousedown",
      ])
      dom.focus(node)
      pointers(node, ["pointerup", "mouseup"])
      dom.click(node)
      unpoint(marker)
      done()
    }
    p.Fill(value) -> {
      use _ <- promise.await(point(node, marker))
      dom.focus(node)
      let result = case dom.flag(node, "isContentEditable"), dom.value(node) {
        True, _ -> {
          dom.set_text(node, "textContent", value)
          let _ = dom.event(node, "input")
          Ok(Nil)
        }
        False, Ok(_) -> {
          set_value(node, value)
          Ok(Nil)
        }
        _, _ ->
          Error("Locator is not an input, textarea or contenteditable element")
      }
      unpoint(marker)
      promise.resolve(result.map(result, fn(_) { protocol.done() }))
    }
    p.SetChecked(value) -> {
      use _ <- promise.await(point(node, marker))
      case dom.flag(node, "checked") == value {
        True -> Nil
        False -> dom.click(node)
      }
      unpoint(marker)
      promise.resolve(case dom.flag(node, "checked") == value {
        True -> Ok(protocol.done())
        False -> Error("Locator did not change checked state")
      })
    }
    p.SelectOption(value) -> {
      let options = dom.query(node, "option") |> result.unwrap([])
      let selected =
        list.find(options, fn(option) {
          dom.value(option) == Ok(value)
          || locator.normalize(dom.text(option, "label"))
          == locator.normalize(value)
        })
      case dom.text(node, "tagName"), selected {
        "SELECT", Ok(option) -> {
          use _ <- promise.await(point(node, marker))
          set_value(node, dom.value(option) |> result.unwrap(""))
          unpoint(marker)
          done()
        }
        "SELECT", Error(_) ->
          promise.resolve(Error("Locator has no option " <> value))
        _, _ -> promise.resolve(Error("Locator is not a select element"))
      }
    }
    p.Hover -> {
      use _ <- promise.await(point(node, marker))
      pointers(node, [
        "pointerover",
        "pointerenter",
        "mouseover",
        "mouseenter",
        "pointermove",
        "mousemove",
      ])
      done()
    }
    p.Focus -> {
      dom.focus(node)
      done()
    }
    p.ScrollIntoView -> {
      dom.scroll(node, "center")
      done()
    }
    p.TextContent -> read(dom.text(node, "textContent"))
    p.InnerText -> read(dom.text(node, "innerText"))
    p.InnerHtml -> read(dom.text(node, "innerHTML"))
    p.InputValue ->
      promise.resolve(
        dom.value(node)
        |> result.map(protocol.text)
        |> result.replace_error(
          "Locator is not an input, textarea or select element",
        ),
      )
    p.GetAttribute(name) ->
      promise.resolve(
        Ok(case dom.attribute(node, name) {
          Ok(value) -> protocol.text(value)
          Error(_) -> protocol.tagged("missing", [])
        }),
      )
    p.IsChecked -> promise.resolve(Ok(protocol.flag(dom.flag(node, "checked"))))
    p.IsEnabled ->
      promise.resolve(Ok(protocol.flag(!dom.flag(node, "disabled"))))
    _ -> promise.resolve(Error("Action should be handled without an element"))
  }
}

fn expect(steps, condition) {
  use nodes <- result.try(locator.resolve(steps) |> result.map_error(Fatal))
  let description = locator.describe(steps)
  case condition {
    p.ToHaveCount(count) ->
      check(
        list.length(nodes) == count,
        "expected "
          <> description
          <> " to have count "
          <> int.to_string(count)
          <> ", found "
          <> int.to_string(list.length(nodes)),
      )
    p.ToBeHidden ->
      check(
        list.all(nodes, fn(node) { !locator.visible(node) }),
        "expected " <> description <> " to be hidden",
      )
    other -> {
      use node <- result.try(case nodes {
        [node] -> Ok(node)
        _ ->
          Error(Retry(
            "expected "
            <> description
            <> " to match one element, found "
            <> int.to_string(list.length(nodes)),
          ))
      })
      let matches = case other {
        p.ToHaveText(text) ->
          locator.normalize(dom.text(node, "textContent"))
          == locator.normalize(text)
        p.ToContainText(text) ->
          locator.includes(dom.text(node, "textContent"), text)
        p.ToBeVisible -> locator.visible(node)
        p.ToHaveValue(value) -> dom.value(node) == Ok(value)
        p.ToHaveAttribute(name, value) -> dom.attribute(node, name) == Ok(value)
        p.ToBeChecked(value) -> dom.flag(node, "checked") == value
        _ -> False
      }
      check(
        matches,
        "expected "
          <> description
          <> " to satisfy "
          <> string.inspect(condition),
      )
    }
  }
}

fn check(matches, failure) {
  case matches {
    True -> Ok(Nil)
    False -> Error(Retry(failure))
  }
}
