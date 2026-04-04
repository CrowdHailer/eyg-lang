import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/publisher
import eyg/hub/signatory
import eyg/ir/dag_json
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import hub/crypto
import hub/packages/data
import hub/server/context
import hub/signatories/data as signatories
import hub/web/utils
import multiformats/cid/v1
import pog
import untethered/ledger/schema
import untethered/ledger/server
import wisp

pub fn submit(request, context: context.Context) {
  use payload <- wisp.require_bit_array_body(request)
  use signature <- utils.try_untethered(server.read_signature(request))
  use entry <- utils.try_untethered(validate_payload(payload))

  let assert Ok(history) = case entry.previous {
    Some(cid) -> {
      todo
      // let assert Ok(rows) = data.list_entries_from_entry(context.db, cid)

      // let assert [previous, ..] = list.reverse(rows)

      // let assert Ok(Nil) = server.validate_integrity(entry, previous.sequence)
      // list.map(rows, fn(row) {
      //   let assert Ok(entry) = json.parse(row.payload, signatory.decoder())

      //   entry.content
      // })
      // |> Ok
    }
    None -> Ok([])
  }
  use Nil <- utils.try_untethered(
    crypto.verify(payload, entry.key, signature)
    |> result.replace_error(server.IncorrectSignature),
  )

  let signatory = v1.to_string(entry.signatory)
  let query = signatories.list_entries_from_entry(signatory)
  let assert Ok(pog.Returned(rows:, ..)) = pog.execute(query, context.db)
  let signatory_history =
    list.map(rows, fn(row) {
      let assert Ok(entry) = json.parse(row.payload, signatory.decoder())

      entry.content
    })
  // let assert [previous, ..] = list.reverse(rows)
  use permission <- utils.try_untethered(
    signatory.fetch_permissions(entry.key, signatory_history)
    |> result.replace_error(server.DoesNotHavePermission),
  )
  echo permission

  use Nil <- utils.try_untethered(authorize(entry.content, permission))

  // TODO test writing permissions
  let query = data.insert_release(entry)
  use archived <- utils.db_result(pog.execute(query, context.db))
  let assert pog.Returned(rows: [entry], ..) = archived
  entry
  |> schema.archived_entry_encode()
  |> json.to_string
  |> wisp.json_response(200)
}

fn validate_payload(payload) {
  server.validate_payload(payload, publisher.decoder())
}

fn authorize(_content, _permission) {
  // As long as they key is in the signatory it has full permission
  Ok(Nil)
}

pub fn pull(request, context) {
  let context.Context(db:, ..) = context
  let parameters = schema.pull_parameters_from_request(request)
  use entries <- utils.db_result(data.list_events(db, parameters))
  schema.entries_response_encode(entries)
  |> json.to_string
  |> wisp.json_response(200)
}
// pub fn packages(context) {
//   let context.Context(db:, ..) = context
//   use packages <- utils.db_call(data.list_packages(db))
//   wisp.response(200)
//   |> wisp.string_body(string.inspect(packages))
// }
