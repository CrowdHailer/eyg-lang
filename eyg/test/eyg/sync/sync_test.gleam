import eyg/sync/cid
import eyg/sync/sync
import eygir/encode
import eygir/expression as e
import gleam/http/response
import gleeunit/should
import gleeunit/shouldx
import midas/task

const origin = sync.test_origin

const just_number = e.Integer(101)

const just_string = e.Str("hello")

pub fn load_references_test() {
  let state = sync.init(origin)
  let ref = cid.for_expression(just_number)

  sync.missing(state, [ref])
  |> shouldx.contain1
  |> should.equal(ref)

  let #(state, tasks) = sync.fetch_missing(state, [ref])
  let #(_ref, task) = shouldx.contain1(tasks)

  let #(state, tasks) = sync.fetch_missing(state, [ref])
  shouldx.be_empty(tasks)

  let #(request, resume) = should.be_ok(task.expect_fetch(task))
  request.host
  |> should.equal("eyg.test")
  request.path
  |> should.equal("/references/" <> ref <> ".json")

  resume(Ok(response.Response(200, [], <<encode.to_json(just_number):utf8>>)))
  |> task.expect_done()
  |> should.be_ok()
  |> should.equal(just_number)

  let state = sync.install(state, ref, just_number)
  sync.missing(state, [ref])
  |> shouldx.be_empty()
}

pub fn load_nested_references_test() {
  let state = sync.init(origin)
  let ref_i = cid.for_expression(just_number)
  let ref_s = cid.for_expression(just_string)

  let source = e.Let("i", e.Reference(ref_i), e.Reference(ref_s))
  let ref = cid.for_expression(source)

  let state = sync.install(state, ref, source)
  sync.missing(state, [ref])
  |> should.equal([ref_i, ref_s])
  let #(state, tasks) = sync.fetch_missing(state, [ref])
  tasks
  |> shouldx.contain2()

  let state = sync.install(state, ref_i, just_number)
  sync.missing(state, [ref])
  |> should.equal([ref_s])
  let #(state, tasks) = sync.fetch_missing(state, [ref])
  tasks
  |> shouldx.be_empty()

  let state = sync.install(state, ref_s, just_string)
  sync.missing(state, [ref])
  |> should.equal([])

  sync.value(state, ref)
  |> should.be_ok
  // |> should.equal(sync.Computed)
}

pub fn load_fails_test() {
  let state = sync.init(origin)
  let ref = cid.for_expression(just_number)

  let #(state, tasks) = sync.fetch_missing(state, [ref])
  let #(_ref, task) = shouldx.contain1(tasks)

  let #(request, resume) = should.be_ok(task.expect_fetch(task))

  let reason =
    resume(Ok(response.Response(404, [], <<>>)))
    |> task.expect_abort()
    |> should.be_ok()

  let state =
    sync.task_finish(state, sync.HashSourceFetched(ref, Error(reason)))
  sync.missing(state, [ref])
  |> should.equal([ref])

  let #(_state, tasks) = sync.fetch_missing(state, [ref])
  let #(_ref, task) = shouldx.contain1(tasks)

  let #(retry, _resume) = should.be_ok(task.expect_fetch(task))
  retry
  |> should.equal(request)
}
// pub fn load_aborting_expression_test() {
//   todo
// }

// pub fn load_type_errors_test() {
//   todo
// }

// pub fn load_returns_incorrect_content() {
//   todo
// }
