--- migration:up

-- What a chat belongs to outside the service, such as a Discord channel.
ALTER TABLE chats ADD COLUMN key TEXT UNIQUE;

--- migration:down

ALTER TABLE chats DROP COLUMN key;

--- migration:end
