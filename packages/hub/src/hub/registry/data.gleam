import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dynamic/decode
import gleam/json
import hub/db/utils
import multiformats/cid/v1
import pog

pub type Module {
  Module(
    cid: v1.Cid,
    // Don't parse source any further as most of the time it's sent over the API
    source: String,
    inserted_at: utils.DateTime,
  )
}

fn module_decoder() {
  use cid <- decode.field(0, utils.cid_decoder())
  use source <- decode.field(1, decode.string)
  use inserted_at <- decode.field(2, utils.datetime_decoder())
  decode.success(Module(cid:, source:, inserted_at:))
}

pub fn insert_module(
  cid: v1.Cid,
  source: #(ir.Expression(a), a),
  ip: String,
) -> pog.Query(Nil) {
  let cid = v1.to_string(cid)
  let serialized = json.to_string(dag_json.to_data_model(source))

  "WITH module_insert AS (
  INSERT INTO modules (cid, source)
  VALUES ($1, $2)
  ON CONFLICT (cid) DO NOTHING
)
INSERT INTO module_uploads (ip, cid)
-- This casting is because pog doesn't expose an inet type
VALUES (($3::text)::inet, $1);"
  |> pog.query()
  |> pog.parameter(pog.text(cid))
  |> pog.parameter(pog.text(serialized))
  |> pog.parameter(pog.text(ip))
}

/// query by string because url parameters arrive as string an it needs reserializing for the query
pub fn get_module(cid: String) -> pog.Query(Module) {
  "SELECT cid, source, inserted_at
FROM modules
WHERE cid = $1
-- AND NOT EXISTS (
--   SELECT 1 FROM blocked_cids b
--  WHERE b.cid = cid
--);"
  |> pog.query()
  |> pog.parameter(pog.text(cid))
  |> pog.returning(module_decoder())
}

// pub fn list_fragments(conn) {
//   "SELECT source, cid, inserted_at FROM fragments"
//   |> pog.query()
//   |> pog.returning(module_decoder())
//   |> pog.execute(conn)
//   |> result.map(fn(returned) { returned.rows })
// }

pub fn count_uploads_by_ip(ip) {
  "SELECT COUNT(*) FROM module_uploads
-- This casting is because pog doesn't expose an inet type
WHERE ip = ($1::text)::inet
AND uploaded_at > now() - interval '10 minutes';"
  |> pog.query()
  |> pog.parameter(pog.text(ip))
  |> pog.returning({
    use count <- decode.field(0, decode.int)
    decode.success(count)
  })
}
