-- restaurant-service schema: restaurants table. Idempotent.
CREATE TABLE IF NOT EXISTS restaurants (
    id          UUID PRIMARY KEY,
    owner_id    UUID NOT NULL,
    name        TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    address     TEXT NOT NULL,
    city        TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'active',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_restaurants_city ON restaurants (city);
CREATE INDEX IF NOT EXISTS idx_restaurants_owner ON restaurants (owner_id);
