import eyg/hub/publisher
import eyg/hub/signatory
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
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

  let assert Ok(_history) = case entry.previous {
    Some(cid) -> {
      let query = data.list_entries_from_entry(cid)
      let assert Ok(pog.Returned(rows:, ..)) = pog.execute(query, context.db)

      let assert [previous, ..] = list.reverse(rows)
      let assert Ok(Nil) = server.validate_integrity(entry, previous.sequence)
      list.map(rows, fn(row) {
        let assert Ok(entry) = json.parse(row.payload, publisher.decoder())

        entry.content
      })
      |> Ok
    }
    None -> Ok([])
  }
  use Nil <- utils.try_untethered(
    crypto.verify(payload, entry.key, signature)
    |> result.replace_error(server.IncorrectSignature),
  )

  let signatory_entity = v1.to_string(entry.signatory)
  let query = signatories.list_entries_from_entry(signatory_entity)
  let assert Ok(pog.Returned(rows:, ..)) = pog.execute(query, context.db)
  let signatory_history =
    list.map(rows, fn(row) {
      let assert Ok(entry) = json.parse(row.payload, signatory.decoder())

      entry.content
    })

  use _permission <- utils.try_untethered(
    signatory.fetch_permissions(entry.key, signatory_history)
    |> result.replace_error(server.DoesNotHavePermission),
  )

  use Nil <- utils.try_untethered(
    check_package_ownership(entry.content, signatory_entity, context.db),
  )

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

fn check_package_ownership(
  content: publisher.Event,
  entity_id: String,
  db: pog.Connection,
) -> Result(Nil, server.Denied) {
  let publisher.Release(package:, ..) = content
  case pog.execute(data.get_current_owner(package), db) {
    Ok(pog.Returned(rows: [], ..)) -> {
      let assert Ok(_) = pog.execute(data.record_owner(package, entity_id), db)
      Ok(Nil)
    }
    Ok(pog.Returned(rows: [owner], ..)) if owner.entity_id == entity_id ->
      Ok(Nil)
    _ -> Error(server.DoesNotHavePermission)
  }
}

pub fn pull(request, context) {
  let context.Context(db:, ..) = context
  let parameters = schema.pull_parameters_from_request(request)
  let query = data.list_events(parameters)
  use pog.Returned(rows:, ..) <- utils.db_result(pog.execute(query, db))
  schema.entries_response_encode(rows)
  |> json.to_string
  |> wisp.json_response(200)
}
