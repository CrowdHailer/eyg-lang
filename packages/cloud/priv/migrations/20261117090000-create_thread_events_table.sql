--- migration:up

-- An append only DAG of events, each one is identified by its parent and its content.
CREATE TABLE thread_events (
  key TEXT PRIMARY KEY,
  parent TEXT REFERENCES thread_events(key),
  -- Text not JSONB, so the payload keeps the exact bytes its key was made from.
  payload TEXT NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX thread_events_parent_idx ON thread_events (parent);

--- migration:down

DROP TABLE thread_events;

--- migration:end
