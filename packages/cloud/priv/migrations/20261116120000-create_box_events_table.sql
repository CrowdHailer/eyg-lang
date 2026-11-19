--- migration:up

-- A box is the chain of file system roots recorded under its name.
CREATE TABLE box_events (
  id BIGSERIAL PRIMARY KEY,
  box TEXT NOT NULL,
  -- sequence is a keyword in SQL
  seq INTEGER NOT NULL,
  root TEXT NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT box_events_sequence_is_positive CHECK (seq >= 1),
  CONSTRAINT box_events_unique_box_sequence UNIQUE (box, seq)
);

--- migration:down

DROP TABLE box_events;

--- migration:end
