-- order-service schema: orders + order_items.
-- Idempotent: safe to run on every startup (search_path is set to "orders").

CREATE TABLE IF NOT EXISTS orders (
    id            UUID PRIMARY KEY,
    customer_id   TEXT        NOT NULL,
    restaurant_id TEXT        NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'PENDING',
    total         NUMERIC(12,2) NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders (customer_id);

CREATE TABLE IF NOT EXISTS order_items (
    id       UUID PRIMARY KEY,
    order_id UUID        NOT NULL REFERENCES orders (id) ON DELETE CASCADE,
    item_id  TEXT        NOT NULL,
    name     TEXT        NOT NULL,
    qty      INT         NOT NULL,
    price    NUMERIC(12,2) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items (order_id);
