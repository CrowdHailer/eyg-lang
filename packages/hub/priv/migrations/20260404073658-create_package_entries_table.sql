--- migration:up

CREATE TABLE package_entries (
  id BIGSERIAL PRIMARY KEY,
  payload JSONB NOT NULL,
  cid TEXT NOT NULL UNIQUE,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  entity TEXT NOT NULL,
  -- sequence is a keyword in SQL
  seq INTEGER GENERATED ALWAYS AS ((payload->>'sequence')::INTEGER) STORED NOT NULL,
  -- Note the `/` to enter the dag json structure
  previous TEXT GENERATED ALWAYS AS (payload->'previous'->>'/') STORED REFERENCES package_entries(cid),
  signatory TEXT GENERATED ALWAYS AS (payload->'signatory'->>'/') STORED REFERENCES signatory_entries(cid),
  type_ TEXT GENERATED ALWAYS AS (payload->>'type') STORED NOT NULL,

  package TEXT GENERATED ALWAYS AS (
    CASE payload->>'type'
        WHEN 'release' THEN payload->'content'->>'package'
        ELSE NULL
    END
  ) STORED NOT NULL,
  
  version_ INTEGER GENERATED ALWAYS AS (
    CASE payload->>'type'
        WHEN 'release' THEN ((payload->'content'->>'version')::INTEGER)
        ELSE NULL
    END
  ) STORED NOT NULL,

  module TEXT GENERATED ALWAYS AS (
    CASE payload->>'type'
        WHEN 'release' THEN payload->'content'->'module'->>'/'
        ELSE NULL
    END
  ) STORED NOT NULL REFERENCES modules(cid),

  CONSTRAINT sequence_is_positive CHECK (seq >= 1),
  CONSTRAINT version_is_positive CHECK (version_ >= 1)
);

CREATE UNIQUE INDEX package_entries_unique_entity_sequence ON package_entries (entity, seq);
CREATE INDEX package_entries_previous_idx ON package_entries (previous);
CREATE RULE protect_package_entries_updates AS ON UPDATE TO package_entries DO INSTEAD NOTHING;
CREATE RULE protect_package_entries_deletes AS ON DELETE TO package_entries DO INSTEAD NOTHING;

CREATE UNIQUE INDEX package_entries_unique_release_version ON package_entries (package, version_);

CREATE OR REPLACE FUNCTION set_package_entry_entity_and_seq()
RETURNS TRIGGER AS $$
DECLARE
  parent_record RECORD;
  -- Extract values directly from payload for validation logic, computed fields are not populated in NEW when the trigger runs
  v_seq INTEGER;
  v_previous TEXT;
BEGIN
  v_seq := (NEW.payload->>'sequence')::INTEGER;
  v_previous := NEW.payload->'previous'->>'/';

  IF v_previous IS NULL THEN
    -- Root record logic
    NEW.entity := NEW.cid;
    
    -- Now this check will actually work
    IF v_seq != 1 THEN
      RAISE EXCEPTION 'Root event (no previous) must have sequence 1, got %', v_seq;
    END IF;
  ELSE
    -- Lookup the parent's entity and sequence
    SELECT entity, seq INTO parent_record 
    FROM package_entries 
    WHERE cid = v_previous;

    -- Safety check: does the parent actually exist?
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Previous event with CID % not found', v_previous;
    END IF;

    -- 1. Inherit the entity
    NEW.entity := parent_record.entity;

    -- 2. Validate the sequence increment
    IF v_seq != (parent_record.seq + 1) THEN
      RAISE EXCEPTION 'Invalid sequence: % (expected % based on previous CID %)', 
        v_seq, (parent_record.seq + 1), v_previous;
    END IF;
  END IF;
  
  -- Since 'entity' is a GENERATED column in your schema, 
  -- note that manually setting NEW.entity here might conflict 
  -- unless you change 'entity' to a standard column.
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_package_entries_validation
BEFORE INSERT ON package_entries
FOR EACH ROW
EXECUTE FUNCTION set_package_entry_entity_and_seq();


CREATE VIEW releases AS
SELECT 
    e.id as event_number,
    e.package,
    e.version_,
    e.module,
    m.source,
    -- (e.payload->>'timestamp')::TIMESTAMPTZ as published_at,
    e.recorded_at
FROM package_entries e
LEFT JOIN modules m ON e.module = m.cid
WHERE e.type_ = 'release'
ORDER BY e.id DESC;

CREATE VIEW latest_releases AS
SELECT DISTINCT ON (package)
    event_number,
    package,
    version_,
    module,
    source,
    -- published_at,
    recorded_at
FROM releases
ORDER BY package, version_ DESC;

--- migration:down

DROP TABLE latest_releases
DROP TABLE releases
DROP TABLE package_entries;

--- migration:end