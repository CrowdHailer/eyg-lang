--- migration:up

-- The session a chat channel, such as a Discord channel, talks to.
CREATE TABLE channel_sessions (
  channel TEXT PRIMARY KEY,
  session TEXT NOT NULL REFERENCES sessions(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

--- migration:down

DROP TABLE channel_sessions;

--- migration:end
