package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/cloudkitchen/notification-service/internal/model"
	"github.com/cloudkitchen/notification-service/internal/repository"
	"github.com/google/uuid"
)

// NotificationService records notifications for every consumed event and "sends"
// a mock email (logged via slog, no real SMTP).
type NotificationService struct {
	repo   *repository.NotificationRepository
	logger *slog.Logger
}

// NewNotificationService constructs the service.
func NewNotificationService(repo *repository.NotificationRepository, logger *slog.Logger) *NotificationService {
	return &NotificationService{repo: repo, logger: logger}
}

// ListRecent returns recent notifications scoped to the given user (empty = all).
func (s *NotificationService) ListRecent(ctx context.Context, userID string, limit int) ([]model.Notification, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	return s.repo.ListRecent(ctx, userID, limit)
}

// HandleEvent is the broker.Handler for order.placed, payment.completed and
// delivery.updated. It derives the recipient + subject, persists a row and logs
// a mock email send.
func (s *NotificationService) HandleEvent(routingKey string, body []byte) error {
	var (
		userID  string
		subject string
	)
	switch routingKey {
	case "order.placed":
		var e model.OrderPlacedEvent
		if err := json.Unmarshal(body, &e); err != nil {
			return fmt.Errorf("unmarshal order.placed: %w", err)
		}
		userID = e.CustomerID
		subject = fmt.Sprintf("Order %s placed (total %.2f)", e.OrderID, e.Total)

	case "payment.completed":
		var e model.PaymentEvent
		if err := json.Unmarshal(body, &e); err != nil {
			return fmt.Errorf("unmarshal payment.completed: %w", err)
		}
		userID = e.OrderID // no customer id on payment event; key by order
		subject = fmt.Sprintf("Payment %s for order %s (amount %.2f)", e.Status, e.OrderID, e.Amount)

	case "delivery.updated":
		var e model.DeliveryEvent
		if err := json.Unmarshal(body, &e); err != nil {
			return fmt.Errorf("unmarshal delivery.updated: %w", err)
		}
		userID = e.OrderID // key by order
		subject = fmt.Sprintf("Delivery %s for order %s", e.Status, e.OrderID)

	default:
		s.logger.Warn("unhandled routing key", "routing_key", routingKey)
		return nil
	}

	n := &model.Notification{
		ID:      uuid.New(),
		UserID:  userID,
		Channel: model.ChannelEmail,
		Type:    routingKey,
		Payload: json.RawMessage(body),
		SentAt:  time.Now().UTC(),
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := s.repo.Create(ctx, n); err != nil {
		return fmt.Errorf("persist notification: %w", err)
	}

	// MOCK email send (no real SMTP).
	s.logger.Info("EMAIL SENT", "to", userID, "subject", subject, "type", routingKey)
	return nil
}
