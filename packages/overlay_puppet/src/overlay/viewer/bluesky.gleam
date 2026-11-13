//// Render public feed records as text; the EYG caller fetches the JSON.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import plinthx/browser/node as dom

pub type Post {
  Post(
    type_: String,
    author: String,
    handle: String,
    created: String,
    text: String,
    likes: Int,
    reposts: Int,
    repost: Bool,
    attachment: Bool,
  )
}

fn post() {
  use repost <- decode.optional_field(
    "reason",
    False,
    decode.map(decode.dynamic, fn(_) { True }),
  )
  use post <- decode.field("post", {
    use author <- decode.optional_field("author", #("", ""), {
      use display <- decode.optional_field("displayName", "", decode.string)
      use handle <- decode.optional_field("handle", "", decode.string)
      decode.success(#(display, handle))
    })
    use likes <- decode.optional_field("likeCount", 0, decode.int)
    use reposts <- decode.optional_field("repostCount", 0, decode.int)
    use record <- decode.field("record", {
      use type_ <- decode.optional_field("$type", "", decode.string)
      use created <- decode.optional_field("createdAt", "", decode.string)
      use text <- decode.optional_field("text", "", decode.string)
      use attachment <- decode.optional_field(
        "embed",
        False,
        decode.map(decode.dynamic, fn(_) { True }),
      )
      decode.success(#(type_, created, text, attachment))
    })
    decode.success(Post(
      record.0,
      author.0,
      author.1,
      record.1,
      record.2,
      likes,
      reposts,
      repost,
      record.3,
    ))
  })
  decode.success(post)
}

fn text(parent, tag, content) {
  let element = dom.create(tag)
  dom.set_text(element, "textContent", content)
  dom.append(parent, element)
}

pub fn main() {
  let assert Ok(root) = dom.by_id("posts")
  let assert Ok(feed) = dom.by_id("feed")
  let decoder =
    decode.field("feed", decode.list(decode.dynamic), decode.success)
  case json.parse(dom.text(feed, "textContent"), decoder) {
    Error(_) ->
      text(
        root,
        "p",
        "Unable to display feed: Expected app.bsky.feed.getAuthorFeed response",
      )
    Ok(raw) -> {
      let posts =
        list.filter_map(raw, fn(raw) { decode.run(raw, post()) })
        |> list.filter(fn(post) { post.type_ == "app.bsky.feed.post" })
      case posts {
        [] -> text(root, "p", "No supported posts in this feed.")
        posts ->
          list.each(posts, fn(post) {
            let card = dom.create("article")
            let author = case post.author, post.handle {
              "", "" -> "Unknown author"
              "", handle -> handle
              name, _ -> name
            }
            text(card, "strong", author)
            text(card, "small", " @" <> post.handle <> " · " <> post.created)
            text(card, "p", post.text)
            text(
              card,
              "small",
              int.to_string(post.likes)
                <> " likes · "
                <> int.to_string(post.reposts)
                <> " reposts",
            )
            case post.repost {
              True -> text(card, "small", " · Reposted")
              False -> Nil
            }
            case post.attachment {
              True ->
                text(
                  card,
                  "p",
                  "[Post contains an attachment; this text viewer does not load remote media.]",
                )
              False -> Nil
            }
            dom.append(root, card)
          })
      }
    }
  }
}
