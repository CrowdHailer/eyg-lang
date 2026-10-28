import eyg/hub/schema.{type ArtifactFile, ArtifactFile}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option}
import hub/db/utils
import pog

/// Store an artifact and its files, returning its id.
pub fn insert(
  name: String,
  files: List(ArtifactFile),
  ip: String,
  secret_hash: BitArray,
) -> pog.Query(String) {
  let paths = list.map(files, fn(file) { file.path })
  let media_types = list.map(files, fn(file) { file.media_type })
  let contents = list.map(files, fn(file) { file.content })
  "WITH artifact AS (
  INSERT INTO artifacts (name, ip, secret_hash)
  -- This casting is because pog doesn't expose an inet type
  VALUES ($1, ($2::text)::inet, $6)
  RETURNING id
), files AS (
  INSERT INTO artifact_files (artifact_id, path, media_type, content)
  SELECT artifact.id, file.path, file.media_type, file.content
  FROM artifact, UNNEST($3::text[], $4::text[], $5::bytea[]) AS file(path, media_type, content)
)
SELECT id::text FROM artifact;"
  |> pog.query()
  |> pog.parameter(pog.text(name))
  |> pog.parameter(pog.text(ip))
  |> pog.parameter(pog.array(pog.text, paths))
  |> pog.parameter(pog.array(pog.text, media_types))
  |> pog.parameter(pog.array(pog.bytea, contents))
  |> pog.parameter(pog.bytea(secret_hash))
  |> pog.returning({
    use id <- decode.field(0, decode.string)
    decode.success(id)
  })
}

/// The id of an artifact that is still served, if the secret it was shared with matches.
pub fn shared_with(id: String, secret_hash: BitArray) -> pog.Query(String) {
  "SELECT id::text FROM artifacts
WHERE id = $1::uuid AND secret_hash = $2 AND withdrawn_at IS NULL;"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.parameter(pog.bytea(secret_hash))
  |> pog.returning({
    use id <- decode.field(0, decode.string)
    decode.success(id)
  })
}

/// Point an artifact to a newer version of it.
pub fn link(id: String, next: String) -> pog.Query(Nil) {
  "UPDATE artifacts SET next_id = $2::uuid WHERE id = $1::uuid;"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.parameter(pog.text(next))
}

pub type Artifact {
  Artifact(name: String, inserted_at: utils.DateTime, next: Option(String))
}

/// Query by string as ids arrive in the URL, the id must already be a valid UUID.
/// A newer version is only given while it is served.
pub fn get(id: String) -> pog.Query(Artifact) {
  "SELECT artifacts.name, artifacts.inserted_at, newer.id::text FROM artifacts
LEFT JOIN artifacts AS newer
  ON newer.id = artifacts.next_id AND newer.withdrawn_at IS NULL
WHERE artifacts.id = $1::uuid AND artifacts.withdrawn_at IS NULL;"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning({
    use name <- decode.field(0, decode.string)
    use inserted_at <- decode.field(1, utils.datetime_decoder())
    use next <- decode.field(2, decode.optional(decode.string))
    decode.success(Artifact(name:, inserted_at:, next:))
  })
}

pub fn files(id: String) -> pog.Query(ArtifactFile) {
  "SELECT path, media_type, content FROM artifact_files
JOIN artifacts ON artifacts.id = artifact_files.artifact_id
WHERE artifact_id = $1::uuid AND withdrawn_at IS NULL
ORDER BY path;"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning(file_decoder())
}

pub fn file(id: String, path: String) -> pog.Query(ArtifactFile) {
  "SELECT path, media_type, content FROM artifact_files
JOIN artifacts ON artifacts.id = artifact_files.artifact_id
WHERE artifact_id = $1::uuid AND path = $2 AND withdrawn_at IS NULL;"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.parameter(pog.text(path))
  |> pog.returning(file_decoder())
}

fn file_decoder() {
  use path <- decode.field(0, decode.string)
  use media_type <- decode.field(1, decode.string)
  use content <- decode.field(2, decode.bit_array)
  decode.success(ArtifactFile(path:, media_type:, content:))
}

pub fn count_by_ip(ip: String) -> pog.Query(Int) {
  "SELECT COUNT(*) FROM artifacts
-- This casting is because pog doesn't expose an inet type
WHERE ip = ($1::text)::inet
AND inserted_at > now() - interval '10 minutes';"
  |> pog.query()
  |> pog.parameter(pog.text(ip))
  |> pog.returning({
    use count <- decode.field(0, decode.int)
    decode.success(count)
  })
}

/// Stop serving an artifact, returning its id if it was being served.
pub fn withdraw(id: String) -> pog.Query(String) {
  "UPDATE artifacts SET withdrawn_at = now()
WHERE id = $1::uuid AND withdrawn_at IS NULL
RETURNING id::text;"
  |> pog.query()
  |> pog.parameter(pog.text(id))
  |> pog.returning({
    use id <- decode.field(0, decode.string)
    decode.success(id)
  })
}
