//// Native DOM node operations. Selection and application behavior belong to Gleam callers.

import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}

pub type Node

pub type Message

pub type Window

@external(javascript, "./node_ffi.mjs", "document")
pub fn document() -> Node

@external(javascript, "./node_ffi.mjs", "root")
pub fn root() -> Node

@external(javascript, "./node_ffi.mjs", "body")
pub fn body() -> Node

@external(javascript, "./node_ffi.mjs", "active")
pub fn active() -> Result(Node, Nil)

@external(javascript, "./node_ffi.mjs", "query")
pub fn query(node: Node, selector: String) -> Result(List(Node), String)

@external(javascript, "./node_ffi.mjs", "getById")
pub fn by_id(id: String) -> Result(Node, Nil)

@external(javascript, "./node_ffi.mjs", "create")
pub fn create(tag: String) -> Node

@external(javascript, "./node_ffi.mjs", "clone")
pub fn clone(node: Node) -> Node

@external(javascript, "./node_ffi.mjs", "append")
pub fn append(node: Node, child: Node) -> Nil

@external(javascript, "./node_ffi.mjs", "remove")
pub fn remove(node: Node) -> Nil

@external(javascript, "./node_ffi.mjs", "replace")
pub fn replace(node: Node, replacement: Node) -> Nil

@external(javascript, "./node_ffi.mjs", "contains")
pub fn contains(node: Node, child: Node) -> Bool

@external(javascript, "./node_ffi.mjs", "labels")
pub fn labels(node: Node) -> List(Node)

@external(javascript, "./node_ffi.mjs", "text")
pub fn text(node: Node, property: String) -> String

@external(javascript, "./node_ffi.mjs", "value")
pub fn value(node: Node) -> Result(String, Nil)

@external(javascript, "./node_ffi.mjs", "setText")
pub fn set_text(node: Node, property: String, value: String) -> Nil

@external(javascript, "./node_ffi.mjs", "flag")
pub fn flag(node: Node, property: String) -> Bool

@external(javascript, "./node_ffi.mjs", "number")
pub fn number(node: Node, property: String) -> Float

@external(javascript, "./node_ffi.mjs", "setNumber")
pub fn set_number(node: Node, property: String, value: Float) -> Nil

@external(javascript, "./node_ffi.mjs", "isType")
pub fn is_type(node: Node, constructor: String) -> Bool

@external(javascript, "./node_ffi.mjs", "attribute")
pub fn attribute(node: Node, name: String) -> Result(String, Nil)

@external(javascript, "./node_ffi.mjs", "setAttribute")
pub fn set_attribute(node: Node, name: String, value: String) -> Nil

@external(javascript, "./node_ffi.mjs", "removeAttribute")
pub fn remove_attribute(node: Node, name: String) -> Nil

@external(javascript, "./node_ffi.mjs", "style")
pub fn style(node: Node, name: String, value: String) -> Nil

@external(javascript, "./node_ffi.mjs", "computedStyle")
pub fn computed_style(node: Node, name: String) -> String

@external(javascript, "./node_ffi.mjs", "checkVisibility")
pub fn check_visibility(node: Node) -> Bool

@external(javascript, "./node_ffi.mjs", "rect")
pub fn rect(node: Node) -> #(Float, Float, Float, Float)

@external(javascript, "./node_ffi.mjs", "focus")
pub fn focus(node: Node) -> Nil

@external(javascript, "./node_ffi.mjs", "click")
pub fn click(node: Node) -> Nil

@external(javascript, "./node_ffi.mjs", "scroll")
pub fn scroll(node: Node, block: String) -> Nil

@external(javascript, "./node_ffi.mjs", "event")
pub fn event(node: Node, name: String) -> Bool

@external(javascript, "./node_ffi.mjs", "keyboard")
pub fn keyboard(node: Node, name: String, key: String) -> Bool

@external(javascript, "./node_ffi.mjs", "pointer")
pub fn pointer(
  node: Node,
  constructor: String,
  name: String,
  x: Float,
  y: Float,
) -> Bool

@external(javascript, "./node_ffi.mjs", "setInheritedValue")
pub fn set_inherited_value(
  node: Node,
  constructor: String,
  value: String,
) -> Nil

@external(javascript, "./node_ffi.mjs", "form")
pub fn form(node: Node) -> Result(Node, Nil)

@external(javascript, "./node_ffi.mjs", "submit")
pub fn submit(node: Node) -> Nil

@external(javascript, "./node_ffi.mjs", "serialize")
pub fn serialize(node: Node) -> String

@external(javascript, "./node_ffi.mjs", "escapeCss")
pub fn escape_css(text: String) -> String

@external(javascript, "./node_ffi.mjs", "encodeUri")
pub fn encode_uri(text: String) -> String

@external(javascript, "./node_ffi.mjs", "windowNumber")
pub fn window_number(property: String) -> Float

@external(javascript, "./node_ffi.mjs", "now")
pub fn now() -> Int

@external(javascript, "./node_ffi.mjs", "sleep")
pub fn sleep(milliseconds: Int) -> Promise(Nil)

@external(javascript, "./node_ffi.mjs", "frame")
pub fn frame() -> Promise(Nil)

@external(javascript, "./node_ffi.mjs", "fontsReady")
pub fn fonts_ready() -> Promise(Nil)

@external(javascript, "./node_ffi.mjs", "onMessage")
pub fn on_message(handle: fn(Message) -> Nil) -> Nil

@external(javascript, "./node_ffi.mjs", "fromParent")
pub fn from_parent(message: Message) -> Bool

@external(javascript, "./node_ffi.mjs", "messageData")
pub fn message_data(message: Message) -> Dynamic

@external(javascript, "./node_ffi.mjs", "postToHost")
pub fn post_to_host(message: String) -> Nil

@external(javascript, "./node_ffi.mjs", "postToFrame")
pub fn post_to_frame(node: Node, message: Dynamic) -> Nil

pub type Event

@external(javascript, "./node_ffi.mjs", "listen")
pub fn listen(node: Node, name: String, handler: fn(Event) -> Nil) -> Nil

@external(javascript, "./node_ffi.mjs", "unlisten")
pub fn unlisten(node: Node, name: String, handler: fn(Event) -> Nil) -> Nil

@external(javascript, "./node_ffi.mjs", "preventDefault")
pub fn prevent_default(event: Event) -> Nil

@external(javascript, "./node_ffi.mjs", "modifier")
pub fn modifier(event: Event, name: String) -> Bool

@external(javascript, "./node_ffi.mjs", "eventText")
pub fn event_text(event: Event, name: String) -> String

@external(javascript, "./node_ffi.mjs", "listenGlobal")
pub fn listen_global(name: String, handler: fn(Event) -> Nil) -> Nil

pub type MediaQuery

@external(javascript, "./node_ffi.mjs", "mediaQuery")
pub fn media_query(query: String) -> MediaQuery

@external(javascript, "./node_ffi.mjs", "mediaMatches")
pub fn media_matches(query: MediaQuery) -> Bool

@external(javascript, "./node_ffi.mjs", "listenMedia")
pub fn listen_media(query: MediaQuery, handler: fn(Event) -> Nil) -> Nil

@external(javascript, "./node_ffi.mjs", "writeStorage")
pub fn write_storage(
  storage: String,
  key: String,
  value: String,
) -> Result(Nil, String)

@external(javascript, "./node_ffi.mjs", "removeStorage")
pub fn remove_storage(storage: String, key: String) -> Result(Nil, String)

@external(javascript, "./node_ffi.mjs", "key")
pub fn key(event: Event) -> String

@external(javascript, "./node_ffi.mjs", "target")
pub fn target(event: Event) -> Node

@external(javascript, "./node_ffi.mjs", "setFlag")
pub fn set_flag(node: Node, property: String, value: Bool) -> Nil

@external(javascript, "./node_ffi.mjs", "tryText")
pub fn try_text(node: Node, property: String) -> Result(String, String)

@external(javascript, "./node_ffi.mjs", "readStorage")
pub fn read_storage(storage: String, key: String) -> Result(String, String)

@external(javascript, "./node_ffi.mjs", "openDatabase")
pub fn open_database(name: String) -> Result(Nil, String)

@external(javascript, "./node_ffi.mjs", "ancestorDocument")
pub fn ancestor_document(window: String) -> Result(Node, String)
