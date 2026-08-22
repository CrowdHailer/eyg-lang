import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import multiformats/cid/v1
import touch_grass/eyg_parse

const cid_string = "bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy"

fn cid() {
  let assert Ok(#(cid, <<>>)) = v1.from_string(cid_string)
  cid
}

pub fn encode_error_is_a_result_test() {
  assert eyg_parse.encode(Error("bad syntax"))
    == v.error(v.String("bad syntax"))
}

pub fn encode_flattens_a_leaf_test() {
  let assert v.Tagged("Ok", v.LinkedList(nodes)) =
    eyg_parse.encode(Ok(ir.integer(42)))
  assert nodes == [v.Tagged("Integer", v.Integer(42))]
}

pub fn encode_flattens_children_in_preorder_test() {
  let node = ir.let_("x", ir.integer(0), ir.variable("x"))
  let assert v.Tagged("Ok", v.LinkedList(nodes)) = eyg_parse.encode(Ok(node))
  assert nodes
    == [
      v.Tagged("Let", v.String("x")),
      v.Tagged("Integer", v.Integer(0)),
      v.Tagged("Variable", v.String("x")),
    ]
}

pub fn encode_flattens_application_arguments_test() {
  let node = ir.apply(ir.variable("f"), ir.variable("a"))
  let assert v.Tagged("Ok", v.LinkedList(nodes)) = eyg_parse.encode(Ok(node))
  assert nodes
    == [
      v.Tagged("Apply", v.unit()),
      v.Tagged("Variable", v.String("f")),
      v.Tagged("Variable", v.String("a")),
    ]
}

pub fn encode_content_reference_test() {
  let assert v.Tagged("Ok", v.LinkedList(nodes)) =
    eyg_parse.encode(Ok(ir.reference(cid())))
  assert nodes == [v.Tagged("ContentReference", v.String(cid_string))]
}

pub fn encode_package_reference_test() {
  let assert v.Tagged("Ok", v.LinkedList(nodes)) =
    eyg_parse.encode(Ok(ir.package("standard")))
  assert nodes == [v.Tagged("PackageReference", v.String("standard"))]
}

pub fn encode_version_reference_test() {
  let assert v.Tagged("Ok", v.LinkedList(nodes)) =
    eyg_parse.encode(Ok(ir.version("standard", 3)))
  assert nodes
    == [
      v.Tagged(
        "VersionReference",
        v.Record(
          dict.from_list([
            #("package", v.String("standard")),
            #("version", v.Integer(3)),
          ]),
        ),
      ),
    ]
}

pub fn encode_release_reference_test() {
  let assert v.Tagged("Ok", v.LinkedList(nodes)) =
    eyg_parse.encode(Ok(ir.release("standard", 3, cid())))
  assert nodes
    == [
      v.Tagged(
        "ReleaseReference",
        v.Record(
          dict.from_list([
            #("package", v.String("standard")),
            #("version", v.Integer(3)),
            #("cid", v.String(cid_string)),
          ]),
        ),
      ),
    ]
}

pub fn encode_relative_reference_test() {
  let assert v.Tagged("Ok", v.LinkedList(nodes)) =
    eyg_parse.encode(Ok(ir.relative("./module.eyg")))
  assert nodes == [v.Tagged("RelativeReference", v.String("./module.eyg"))]
}
