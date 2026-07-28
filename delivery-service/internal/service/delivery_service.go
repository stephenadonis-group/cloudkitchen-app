package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/cloudkitchen/delivery-service/internal/model"
	"github.com/cloudkitchen/delivery-service/internal/repository"
	"github.com/cloudkitchen/delivery-service/pkg/broker"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// ErrNoAgent is returned when no delivery agent is available for assignment.
var ErrNoAgent = errors.New("no delivery agent available")

// ErrInvalidStatus is returned for an unsupported status transition.
var ErrInvalidStatus = errors.New("invalid delivery status")

// DeliveryService assigns agents on payment completion and exposes status updates.
type DeliveryService struct {
	repo   *repository.DeliveryRepository
	broker *broker.Broker
	logger *slog.Logger
}

// NewDeliveryService constructs the service.
func NewDeliveryService(repo *repository.DeliveryRepository, b *broker.Broker, logger *slog.Logger) *DeliveryService {
	return &DeliveryService{repo: repo, broker: b, logger: logger}
}

// HandleEvent is the broker.Handler for payment.completed.
func (s *DeliveryService) HandleEvent(routingKey string, body []byte) error {
	if routingKey != "payment.completed" {
		s.logger.Warn("unhandled routing key", "routing_key", routingKey)
		return nil
	}
	var e model.PaymentEvent
	if err := json.Unmarshal(body, &e); err != nil {
		return fmt.Errorf("unmarshal payment.completed: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	d, err := s.repo.AssignAndCreate(ctx, e.OrderID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// No agent free right now; nack+requeue so it can retry later.
			s.logger.Warn("no agent available, will retry", "order_id", e.OrderID)
			return ErrNoAgent
		}
		return fmt.Errorf("assign delivery: %w", err)
	}

	s.publishUpdated(d)
	s.logger.Info("delivery assigned", "order_id", e.OrderID, "delivery_id", d.ID, "agent_id", d.AgentID)
	return nil
}

// UpdateStatus validates and applies an agent-driven status change, publishing
// delivery.updated on success.
func (s *DeliveryService) UpdateStatus(ctx context.Context, id uuid.UUID, status string) (*model.Delivery, error) {
	if !model.ValidStatus(status) {
		return nil, ErrInvalidStatus
	}
	d, err := s.repo.UpdateStatus(ctx, id, status)
	if err != nil {
		return nil, err
	}
	s.publishUpdated(d)
	return d, nil
}

// GetByOrderID returns the delivery for an order.
func (s *DeliveryService) GetByOrderID(ctx context.Context, orderID string) (*model.Delivery, error) {
	return s.repo.GetByOrderID(ctx, orderID)
}

// publishUpdated emits a delivery.updated event (best-effort: logs on failure).
func (s *DeliveryService) publishUpdated(d *model.Delivery) {
	agentID := ""
	if d.AgentID != nil {
		agentID = d.AgentID.String()
	}
	evt := model.DeliveryEvent{
		OrderID:    d.OrderID,
		DeliveryID: d.ID.String(),
		Status:     d.Status,
		AgentID:    agentID,
	}
	if err := s.broker.Publish("delivery.updated", evt); err != nil {
		s.logger.Error("failed to publish delivery.updated", "delivery_id", d.ID, "error", err)
	}
}
