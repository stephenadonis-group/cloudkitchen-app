package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"math/rand"
	"time"

	"github.com/cloudkitchen/payment-service/internal/model"
	"github.com/cloudkitchen/payment-service/internal/repository"
	"github.com/cloudkitchen/payment-service/pkg/broker"
	"github.com/google/uuid"
)

// PaymentService processes payments in response to order.placed events and
// publishes payment.completed / payment.failed.
type PaymentService struct {
	repo   *repository.PaymentRepository
	broker *broker.Broker
	logger *slog.Logger
}

// NewPaymentService constructs the service.
func NewPaymentService(repo *repository.PaymentRepository, b *broker.Broker, logger *slog.Logger) *PaymentService {
	return &PaymentService{repo: repo, broker: b, logger: logger}
}

// GetByOrderID returns the latest payment for an order.
func (s *PaymentService) GetByOrderID(ctx context.Context, orderID string) (*model.Payment, error) {
	return s.repo.GetByOrderID(ctx, orderID)
}

// HandleEvent is the broker.Handler for order.placed.
func (s *PaymentService) HandleEvent(routingKey string, body []byte) error {
	if routingKey != "order.placed" {
		s.logger.Warn("unhandled routing key", "routing_key", routingKey)
		return nil
	}
	var e model.OrderPlacedEvent
	if err := json.Unmarshal(body, &e); err != nil {
		return fmt.Errorf("unmarshal order.placed: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// MOCK payment processing: small delay, then a (mostly) successful outcome.
	time.Sleep(200 * time.Millisecond)
	status := model.StatusSuccess
	// 10% simulated failure rate to exercise the failure path.
	if rand.Float64() < 0.10 {
		status = model.StatusFailed
	}

	payment := &model.Payment{
		ID:        uuid.New(),
		OrderID:   e.OrderID,
		Amount:    e.Total,
		Method:    "CARD",
		Status:    status,
		CreatedAt: time.Now().UTC(),
	}
	if err := s.repo.Create(ctx, payment); err != nil {
		return fmt.Errorf("persist payment: %w", err)
	}

	evt := model.PaymentEvent{
		OrderID:   payment.OrderID,
		PaymentID: payment.ID.String(),
		Status:    payment.Status,
		Amount:    payment.Amount,
	}
	routing := "payment.completed"
	if status == model.StatusFailed {
		routing = "payment.failed"
	}
	if err := s.broker.Publish(routing, evt); err != nil {
		return fmt.Errorf("publish %s: %w", routing, err)
	}
	s.logger.Info("payment processed", "order_id", e.OrderID, "status", status, "payment_id", payment.ID)
	return nil
}
