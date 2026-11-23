--- migration:up

-- Secrets code in a box can read with the Env effect. A clone starts with a copy of them.
CREATE TABLE box_secrets (
  box TEXT NOT NULL REFERENCES boxes(id),
  name TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (box, name)
);

--- migration:down

DROP TABLE box_secrets;

--- migration:end
