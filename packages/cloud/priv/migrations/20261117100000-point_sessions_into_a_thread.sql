--- migration:up

-- A session is a pointer to the last event of its history in a thread.
ALTER TABLE sessions ADD COLUMN head TEXT REFERENCES thread_events(key);

DROP TABLE session_turns;

-- The change a box event merged, so merging the same change into the box again does nothing.
ALTER TABLE box_events ADD COLUMN change TEXT;
ALTER TABLE box_events ADD CONSTRAINT box_events_unique_change UNIQUE (box, change);

--- migration:down

ALTER TABLE box_events DROP CONSTRAINT box_events_unique_change;
ALTER TABLE box_events DROP COLUMN change;

CREATE TABLE session_turns (
  id BIGSERIAL PRIMARY KEY,
  session TEXT NOT NULL REFERENCES sessions(id),
  code TEXT NOT NULL,
  output JSONB NOT NULL,
  value TEXT,
  error TEXT,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX session_turns_session_idx ON session_turns (session);

ALTER TABLE sessions DROP COLUMN head;

--- migration:end
