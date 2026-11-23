--- migration:up

-- A box is a file system that changes over time. A named box is shared, a box without a name is transient.
-- `name` is the box's current name.
CREATE TABLE boxes (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  name TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Each change to a box is the next event in its sequence.
-- An event sets the root of its file system, its name, or both. A column that is NULL is unchanged,
-- so the root at an event is the root of the latest event at or before it that has one.
CREATE TABLE box_events (
  box TEXT NOT NULL REFERENCES boxes(id),
  -- sequence is a keyword in SQL
  seq INTEGER NOT NULL,
  root TEXT,
  name TEXT,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  PRIMARY KEY (box, seq),
  CONSTRAINT box_events_sequence_is_positive CHECK (seq >= 1),
  CONSTRAINT box_events_change_something CHECK (root IS NOT NULL OR name IS NOT NULL)
);

--- migration:down

DROP TABLE box_events;
DROP TABLE boxes;

--- migration:end
