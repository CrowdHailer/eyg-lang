--- migration:up

-- The crons of a box, from its /_box/config.eyg module. Each runs its code in its own shell in the box.
-- `next_run`, in seconds since the Unix epoch, is claimed by moving it forward, so each run happens once.
CREATE TABLE crons (
  box TEXT NOT NULL REFERENCES boxes(id),
  name TEXT NOT NULL,
  schedule TEXT NOT NULL,
  shell TEXT NOT NULL REFERENCES shells(id),
  next_run BIGINT NOT NULL,
  PRIMARY KEY (box, name)
);

--- migration:down

DROP TABLE crons;

--- migration:end
