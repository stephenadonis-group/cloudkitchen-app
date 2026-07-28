-- notification-service schema: notifications.
-- Idempotent: safe to run on every startup (search_path set to "notifications").

CREATE TABLE IF NOT EXISTS notifications (
    id      UUID PRIMARY KEY,
    user_id TEXT        NOT NULL,
    channel TEXT        NOT NULL,
    type    TEXT        NOT NULL,
    payload JSONB       NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications (user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_sent_at ON notifications (sent_at DESC);
