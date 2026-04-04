--- migration:up

CREATE TABLE signatory_entries (
  id BIGSERIAL PRIMARY KEY,
  payload JSONB NOT NULL,
  cid TEXT NOT NULL UNIQUE,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  entity TEXT NOT NULL,
  -- sequence is a keyword in SQL
  seq INTEGER GENERATED ALWAYS AS ((payload->>'sequence')::INTEGER) STORED NOT NULL,
  -- Note the `/` to enter the dag json structure
  previous TEXT GENERATED ALWAYS AS (payload->'previous'->>'/') STORED REFERENCES signatory_entries(cid),
  type_ TEXT GENERATED ALWAYS AS (payload->>'type') STORED NOT NULL,

  CONSTRAINT sequence_is_positive CHECK (seq >= 1)
);

CREATE UNIQUE INDEX signatory_entries_unique_entity_sequence ON signatory_entries (entity, seq);
CREATE INDEX signatory_entries_previous_idx ON signatory_entries (previous);
CREATE RULE protect_signatory_entries_updates AS ON UPDATE TO signatory_entries DO INSTEAD NOTHING;
CREATE RULE protect_signatory_entries_deletes AS ON DELETE TO signatory_entries DO INSTEAD NOTHING;

CREATE OR REPLACE FUNCTION set_signatory_entries_entity_and_seq()
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
    FROM signatory_entries 
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

CREATE TRIGGER trigger_signatory_entries_validation
BEFORE INSERT ON signatory_entries
FOR EACH ROW
EXECUTE FUNCTION set_signatory_entries_entity_and_seq();

--- migration:down

DROP TABLE signatory_entries;
DROP FUNCTION set_signatory_entries_entity_and_seq();

--- migration:end