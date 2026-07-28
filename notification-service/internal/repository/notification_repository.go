package repository

import (
	"context"
	"fmt"

	"github.com/cloudkitchen/notification-service/internal/model"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// NotificationRepository persists notification records.
type NotificationRepository struct {
	pool *pgxpool.Pool
}

// NewNotificationRepository wires the repository to a pgx pool.
func NewNotificationRepository(pool *pgxpool.Pool) *NotificationRepository {
	return &NotificationRepository{pool: pool}
}

// Create inserts a notification row.
func (r *NotificationRepository) Create(ctx context.Context, n *model.Notification) error {
	if _, err := r.pool.Exec(ctx,
		`INSERT INTO notifications (id, user_id, channel, type, payload, sent_at)
		 VALUES ($1,$2,$3,$4,$5,$6)`,
		n.ID, n.UserID, n.Channel, n.Type, []byte(n.Payload), n.SentAt,
	); err != nil {
		return fmt.Errorf("insert notification: %w", err)
	}
	return nil
}

// ListRecent returns the most recent notifications. When userID is empty (admin),
// all users' notifications are returned; otherwise it is scoped to that user.
func (r *NotificationRepository) ListRecent(ctx context.Context, userID string, limit int) ([]model.Notification, error) {
	var (
		rows pgx.Rows
		err  error
	)
	if userID == "" {
		rows, err = r.pool.Query(ctx,
			`SELECT id, user_id, channel, type, payload, sent_at
			 FROM notifications ORDER BY sent_at DESC LIMIT $1`, limit)
	} else {
		rows, err = r.pool.Query(ctx,
			`SELECT id, user_id, channel, type, payload, sent_at
			 FROM notifications WHERE user_id=$1 ORDER BY sent_at DESC LIMIT $2`, userID, limit)
	}
	if err != nil {
		return nil, fmt.Errorf("query notifications: %w", err)
	}
	defer rows.Close()

	var out []model.Notification
	for rows.Next() {
		var n model.Notification
		var payload []byte
		if err := rows.Scan(&n.ID, &n.UserID, &n.Channel, &n.Type, &payload, &n.SentAt); err != nil {
			return nil, fmt.Errorf("scan notification: %w", err)
		}
		n.Payload = payload
		out = append(out, n)
	}
	return out, rows.Err()
}
