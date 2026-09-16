import gleam/option.{None, Some}
import multiformats/cid/v1
import overlay/web/context

const example = "bafyreigdmqpykrgxyahdnfmfzmc5j4bkwci6wf6fkdbapq7hfpmg2j3yqy"

fn example_cid() {
  let assert Ok(#(cid, <<>>)) = v1.from_string(example)
  cid
}

pub fn no_parameters_is_the_default_context_test() {
  assert context.Default == context.from_query([])
  assert context.Default == context.from_query([#("other", "value")])
  assert context.Default == context.from_search("")
}

pub fn malformed_query_is_an_invalid_context_test() {
  let assert context.Invalid(raw:, reason:) = context.from_search("?package=%")
  assert "?package=%" == raw
  assert "The context query could not be parsed." == reason
}

pub fn reference_parameter_test() {
  assert context.Reference(example_cid())
    == context.from_search("?reference=" <> example)
}

pub fn an_entire_reference_must_be_valid_test() {
  let assert context.Invalid(raw:, reason:) =
    context.from_query([#("reference", example <> "extra")])
  assert "#" <> example <> "extra" == raw
  assert "Not a valid reference: " <> example <> "extra" == reason
}

pub fn invalid_reference_parameter_test() {
  let assert context.Invalid(raw:, reason:) =
    context.from_query([#("reference", "not-a-cid")])
  assert "#not-a-cid" == raw
  assert "Not a valid reference: not-a-cid" == reason
}

pub fn package_parameter_test() {
  assert context.Package("example", None)
    == context.from_query([#("package", "example")])
}

pub fn release_parameter_test() {
  assert context.Package("example", Some(3))
    == context.from_search("?package=example&version=3")
}

pub fn invalid_version_parameter_test() {
  let assert context.Invalid(raw:, reason:) =
    context.from_query([#("package", "example"), #("version", "latest")])
  assert "@example:latest" == raw
  assert "Not a valid version: latest" == reason
}

pub fn a_release_version_must_be_positive_test() {
  let assert context.Invalid(reason:, ..) =
    context.from_query([#("package", "example"), #("version", "0")])
  assert "Version must be greater than zero: 0" == reason
}

pub fn version_requires_a_package_test() {
  let assert context.Invalid(raw:, reason:) =
    context.from_query([#("version", "3")])
  assert "?version=3" == raw
  assert "The version parameter requires a package." == reason

  let assert context.Invalid(raw:, reason:) =
    context.from_query([#("reference", example), #("version", "3")])
  assert "?reference=" <> example <> "&version=3" == raw
  assert "The version parameter requires a package." == reason
}

pub fn reference_and_package_parameter_test() {
  let assert context.Invalid(raw: _, reason:) =
    context.from_query([#("reference", example), #("package", "example")])
  assert "Set only one of the reference and package parameters." == reason
}
