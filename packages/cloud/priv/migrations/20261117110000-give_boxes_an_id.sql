--- migration:up

-- A box points at a file system root, its events are the roots it has pointed at.
-- A named box is shared, a box without a name is transient and only reached through its id.
CREATE TABLE boxes (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  name TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Boxes that were only a name keep it as their id.
INSERT INTO boxes (id, name)
SELECT box, box FROM box_events
UNION
SELECT box, box FROM sessions;

ALTER TABLE box_events ADD CONSTRAINT box_events_box_fkey FOREIGN KEY (box) REFERENCES boxes(id);
ALTER TABLE sessions ADD CONSTRAINT sessions_box_fkey FOREIGN KEY (box) REFERENCES boxes(id);

--- migration:down

ALTER TABLE sessions DROP CONSTRAINT sessions_box_fkey;
ALTER TABLE box_events DROP CONSTRAINT box_events_box_fkey;
DROP TABLE boxes;

--- migration:end
