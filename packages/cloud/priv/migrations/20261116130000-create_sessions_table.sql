--- migration:up

CREATE TABLE sessions (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  box TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX sessions_box_idx ON sessions (box);

-- Every piece of code run in a session and what came of it.
CREATE TABLE session_turns (
  id BIGSERIAL PRIMARY KEY,
  session TEXT NOT NULL REFERENCES sessions(id),
  code TEXT NOT NULL,
  output JSONB NOT NULL,
  -- Exactly one of value and error is set.
  value TEXT,
  error TEXT,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX session_turns_session_idx ON session_turns (session);

--- migration:down

DROP TABLE session_turns;
DROP TABLE sessions;

--- migration:end
