import cloud/beam/execute
import cloud/box
import cloud/box/check
import cloud/box/interface
import cloud/box/transaction as tx
import cloud/templates
import eyg/hub/cache
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleeunit/should
import ogre/origin

pub fn all_templates_check_and_execute_test() {
  let templates = templates.all()
  list.length(templates) |> should.equal(20)
  templates
  |> list.map(fn(template) { template.id })
  |> list.unique
  |> list.length
  |> should.equal(20)
  list.each(templates, fn(template) {
    let initial = box.empty()
    let runtime =
      execute.State(origin.http("localhost"), cache.ready(), dict.new())
    let assert Ok(files) =
      tx.prepare(initial.files, initial.files.root, template.files, fn(_) {
        True
      })
    let assert Ok(#(modules, runtime)) = check.validate(files, runtime)
      as template.id
    let assert Ok(runtime) = interface.validate(modules, runtime) as template.id
    let assert Ok(module) = dict.get(modules, "/system/http.eyg")
    let assert Ok(config) = interface.decode(module.value)
    let request =
      v.Record(
        dict.from_list([
          #("method", v.String("POST")),
          #("path", v.String("/")),
          #("body", v.Binary(<<"2":utf8>>)),
          #("headers", v.LinkedList([])),
        ]),
      )
    let #(outcome, _, _) =
      execute.call_value(
        config.handler,
        request,
        runtime,
        config.policy,
        files,
        fn(_) { Nil },
      )
    let assert Ok(_) = outcome as template.id
    list.each(interface.crons(modules), fn(cron) {
      let #(outcome, _, _) =
        execute.call_value(
          cron.config.handler,
          v.unit(),
          runtime,
          cron.config.policy,
          files,
          fn(_) { Nil },
        )
      outcome |> should.equal(Ok(v.unit()))
    })
  })
}
