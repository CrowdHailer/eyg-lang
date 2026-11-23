--- migration:up

-- A shell runs code in a box.
CREATE TABLE shells (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  box TEXT NOT NULL REFERENCES boxes(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- So the journal can require its box is the shell's box.
  UNIQUE (id, box)
);

CREATE INDEX shells_box_idx ON shells (box);

-- What happened in a shell, in order. Entries are only ever appended.
-- An input is what the next segment of code runs with, it records the box event the segment starts from.
-- An output is what the segment did, it is recorded with the box event of its change, if any.
CREATE TABLE journal (
  shell TEXT NOT NULL,
  box TEXT NOT NULL,
  seq INTEGER NOT NULL,
  start INTEGER,
  entry JSONB NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

  PRIMARY KEY (shell, seq),
  CONSTRAINT journal_sequence_is_positive CHECK (seq >= 1),
  FOREIGN KEY (shell, box) REFERENCES shells(id, box),
  FOREIGN KEY (box, start) REFERENCES box_events(box, seq)
);

--- migration:down

DROP TABLE journal;
DROP TABLE shells;

--- migration:end
