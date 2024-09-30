import eyg/sync/cid
import gleam/bit_array
import gleam/dict
import javascript/mutable_reference as ref
import lustre/attribute as a
import lustre/element/html as h

pub type MediaType {
  Js
  Css
}

pub type Asset {
  Asset(name: String, bytes: BitArray, ext: MediaType)
}

pub fn css(name, content) {
  Asset(name, bit_array.from_string(content), Css)
}

pub fn js(name, content) {
  Asset(name, bit_array.from_string(content), Js)
}

pub type Bundle {
  Bundle(root: String, store: ref.MutableReference(dict.Dict(String, BitArray)))
}

pub fn new_bundle(root) {
  Bundle(root, ref.new(dict.new()))
}

pub fn to_files(bundle) {
  let Bundle(_, store) = bundle
  ref.get(store) |> dict.to_list
}

pub fn resource(asset, bundle) {
  let Asset(name, bytes, type_) = asset
  let assert Ok(bs) = bit_array.to_string(bytes)
  let hash = cid.hash_code(bs)
  let ext = case type_ {
    Js -> "js"
    Css -> "css"
  }
  let id = name <> "-" <> hash <> "." <> ext

  let Bundle(root, store) = bundle
  let path = root <> "/" <> id
  ref.update(store, dict.insert(_, path, bytes))

  case type_ {
    Js ->
      h.script(
        [a.attribute("defer", ""), a.attribute("async", ""), a.src(path)],
        "",
      )
    Css -> h.link([a.rel("stylesheet"), a.href(path)])
  }
}
