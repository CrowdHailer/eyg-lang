-- TODO organisations

CREATE TABLE boxes (
  id TEXT PRIMARY KEY,
  name TEXT UNIQUE,                       -- NULL: a transient box
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE box_revisions (
  box TEXT NOT NULL REFERENCES boxes(id),
  seq INTEGER NOT NULL CHECK (seq >= 1),
  root TEXT NOT NULL, -- As this is a CID should it be saved in binary
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (box, seq)

  CONSTRAINT box_revisions_sequence_is_positive CHECK (seq >= 1),
  CONSTRAINT box_revisions_unique_box_sequence UNIQUE (box, seq)
);

-- TODO create parents so session has parent_id parent_sequence

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  box TEXT NOT NULL REFERENCES boxes(id),
  -- llm TEXT,                               -- NULL: a shell session
  key TEXT UNIQUE,                        -- e.g. discord:<thread id>, cron:<box>:<name>
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE session_events (
  session TEXT NOT NULL REFERENCES sessions(id),
  seq INTEGER NOT NULL CHECK (seq >= 1),
  payload JSONB NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (session, seq)
);

