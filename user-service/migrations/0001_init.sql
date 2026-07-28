-- user-service schema: profiles and addresses. Idempotent.
CREATE TABLE IF NOT EXISTS profiles (
    user_id   UUID PRIMARY KEY,
    full_name TEXT NOT NULL DEFAULT '',
    phone     TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS addresses (
    id         UUID PRIMARY KEY,
    user_id    UUID NOT NULL,
    line1      TEXT NOT NULL,
    city       TEXT NOT NULL,
    pincode    TEXT NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_addresses_user_id ON addresses (user_id);
