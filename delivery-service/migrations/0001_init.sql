-- delivery-service schema: agents + deliveries.
-- Idempotent: safe to run on every startup (search_path set to "delivery").

CREATE TABLE IF NOT EXISTS agents (
    id        UUID PRIMARY KEY,
    name      TEXT    NOT NULL,
    phone     TEXT    NOT NULL,
    available BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS deliveries (
    id         UUID PRIMARY KEY,
    order_id   TEXT        NOT NULL,
    agent_id   UUID        REFERENCES agents (id),
    status     TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_deliveries_order_id ON deliveries (order_id);

-- Seed 10 delivery agents (idempotent via fixed UUIDs + ON CONFLICT).
-- Sized for a smoke test / classroom demo: the assigner picks the first
-- agent with available=TRUE; once an order is DELIVERED the agent flips
-- back to TRUE. With only 3 we burned the entire pool during testing and
-- new orders failed with "no agent available". 10 leaves plenty of slack.
INSERT INTO agents (id, name, phone, available) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Alice Rider',     '+1-555-0101', TRUE),
    ('22222222-2222-2222-2222-222222222222', 'Bob Courier',     '+1-555-0102', TRUE),
    ('33333333-3333-3333-3333-333333333333', 'Carol Wheels',    '+1-555-0103', TRUE),
    ('44444444-4444-4444-4444-444444444444', 'Dan Dasher',      '+1-555-0104', TRUE),
    ('55555555-5555-5555-5555-555555555555', 'Eve Express',     '+1-555-0105', TRUE),
    ('66666666-6666-6666-6666-666666666666', 'Frank Flyer',     '+1-555-0106', TRUE),
    ('77777777-7777-7777-7777-777777777777', 'Grace Glide',     '+1-555-0107', TRUE),
    ('88888888-8888-8888-8888-888888888888', 'Henry Hustle',    '+1-555-0108', TRUE),
    ('99999999-9999-9999-9999-999999999999', 'Ivy Instant',     '+1-555-0109', TRUE),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Jack Jet',        '+1-555-0110', TRUE)
ON CONFLICT (id) DO NOTHING;
