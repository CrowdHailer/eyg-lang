--- migration:up

CREATE TABLE package_owners (
  id BIGSERIAL PRIMARY KEY,
  package TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE RULE protect_package_owners_updates AS ON UPDATE TO package_owners DO INSTEAD NOTHING;
CREATE RULE protect_package_owners_deletes AS ON DELETE TO package_owners DO INSTEAD NOTHING;

CREATE VIEW current_package_owners AS
SELECT DISTINCT ON (package)
  package,
  entity_id,
  recorded_at
FROM package_owners
ORDER BY package, id DESC;

--- migration:down

DROP VIEW current_package_owners;
DROP TABLE package_owners;

--- migration:end
