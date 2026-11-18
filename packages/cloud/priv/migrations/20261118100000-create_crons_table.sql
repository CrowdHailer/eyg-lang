--- migration:up

-- The crons of a box, from its /crons.json file. Each runs its code in its own session in the box.
-- `next_run`, in seconds since the Unix epoch, is claimed by moving it forward, so each run happens once.
CREATE TABLE crons (
  box TEXT NOT NULL REFERENCES boxes(id),
  name TEXT NOT NULL,
  schedule TEXT NOT NULL,
  session TEXT NOT NULL REFERENCES sessions(id),
  next_run BIGINT NOT NULL,
  PRIMARY KEY (box, name)
);

--- migration:down

DROP TABLE crons;

--- migration:end
