-- payment-service schema: payments.
-- Idempotent: safe to run on every startup (search_path set to "payments").

CREATE TABLE IF NOT EXISTS payments (
    id         UUID PRIMARY KEY,
    order_id   TEXT        NOT NULL,
    amount     NUMERIC(12,2) NOT NULL,
    method     TEXT        NOT NULL DEFAULT 'CARD',
    status     TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payments_order_id ON payments (order_id);
