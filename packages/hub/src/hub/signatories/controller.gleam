import eyg/hub/signatory
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import hub/cid
import hub/crypto
import hub/server/context
import hub/signatories/data
import hub/web/utils
import multiformats/cid/v1
import pog
import untethered/ledger/schema
import untethered/ledger/server
import wisp

pub fn submit(request, context: context.Context) {
  use payload <- wisp.require_bit_array_body(request)
  use signature <- utils.try_untethered(server.read_signature(request))
  use entry <- utils.try_untethered(server.validate_payload(
    payload,
    signatory.decoder(),
  ))

  let assert Ok(history) = case entry.previous {
    Some(cid) -> {
      let cid = v1.to_string(cid)
      let query = data.list_entries_from_entry(cid)
      let assert Ok(pog.Returned(rows:, ..)) = pog.execute(query, context.db)
      let assert [previous, ..] = list.reverse(rows)

      let assert Ok(Nil) = server.validate_integrity(entry, previous.sequence)
      list.map(rows, fn(row) {
        let assert Ok(entry) = json.parse(row.payload, signatory.decoder())

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

  use permission <- utils.try_untethered(
    signatory.fetch_permissions(entry.key, history)
    |> result.replace_error(server.DoesNotHavePermission),
  )
  use Nil <- utils.try_untethered(authorize(entry.content, permission))

  let cid = cid.from_block(payload)
  let query = data.insert_entry(cid, signatory.encode(entry))
  use pog.Returned(rows:, ..) <- utils.db_result(pog.execute(query, context.db))
  let assert [entry] = rows

  entry
  |> schema.archived_entry_encode
  |> json.to_string
  |> wisp.json_response(200)
}

fn authorize(content, permission) {
  case content, permission {
    signatory.AddKey(_key), signatory.Admin -> Ok(Nil)
    signatory.AddKey(key), signatory.AddSelf(self) if key == self -> Ok(Nil)
    _, _ -> Error(server.DoesNotHavePermission)
  }
}

pub fn pull(request, context: context.Context) {
  let query = wisp.get_query(request)
  let parameters = schema.pull_parameters_from_query(query)

  echo parameters
  let query = data.list_entries(parameters)
  use pog.Returned(rows:, ..) <- utils.db_result(pog.execute(query, context.db))

  schema.entries_response_encode(rows)
  |> json.to_string()
  |> wisp.json_response(200)
}
