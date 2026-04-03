import eyg/hub/schema
import pog

pub fn insert_release(cid, entry) {
  todo
}

pub fn list_events(
  db: pog.Connection,
  parameters: schema.PullParameters,
) -> Result(List(schema.ArchivedEntry), pog.QueryError) {
  todo
}
