package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/cloudkitchen/order-service/internal/model"
	"github.com/cloudkitchen/order-service/internal/repository"
	"github.com/cloudkitchen/order-service/pkg/broker"
	"github.com/google/uuid"
)

// ErrEmptyCart is returned when checkout is attempted with no cart items.
var ErrEmptyCart = errors.New("cart is empty")

// OrderService coordinates order creation, history reads and event-driven status
// transitions. It depends on the order repository, cart service and event broker.
type OrderService struct {
	repo       *repository.OrderRepository
	cart       *CartService
	broker     *broker.Broker
	logger     *slog.Logger
	menuURL    string
	httpClient *http.Client
}

// NewOrderService constructs the service.
func NewOrderService(repo *repository.OrderRepository, cart *CartService, b *broker.Broker, menuURL string, logger *slog.Logger) *OrderService {
	return &OrderService{
		repo:       repo,
		cart:       cart,
		broker:     b,
		logger:     logger,
		menuURL:    menuURL,
		httpClient: &http.Client{Timeout: 2 * time.Second},
	}
}

// PlaceOrder reads the customer's cart, best-effort validates items against the
// menu-service, persists the order (PENDING) + items, clears the cart and
// publishes "order.placed".
func (s *OrderService) PlaceOrder(ctx context.Context, customerID, restaurantID string) (*model.Order, error) {
	cart, err := s.cart.Get(ctx, customerID)
	if err != nil {
		return nil, err
	}
	if len(cart.Items) == 0 {
		return nil, ErrEmptyCart
	}

	// Best-effort menu validation: never blocks checkout on failure.
	s.validateItems(ctx, cart)

	order := &model.Order{
		ID:           uuid.New(),
		CustomerID:   customerID,
		RestaurantID: restaurantID,
		Status:       model.StatusPending,
		Total:        cart.Total(),
		CreatedAt:    time.Now().UTC(),
	}
	for _, it := range cart.Items {
		order.Items = append(order.Items, model.OrderItem{
			ItemID: it.ItemID,
			Name:   it.Name,
			Qty:    it.Qty,
			Price:  it.Price,
		})
	}

	if err := s.repo.Create(ctx, order); err != nil {
		return nil, err
	}

	if err := s.cart.Clear(ctx, customerID); err != nil {
		s.logger.Warn("failed to clear cart after order", "customer_id", customerID, "error", err)
	}

	evt := model.OrderPlacedEvent{
		OrderID:      order.ID.String(),
		CustomerID:   order.CustomerID,
		RestaurantID: order.RestaurantID,
		Total:        order.Total,
	}
	if err := s.broker.Publish("order.placed", evt); err != nil {
		s.logger.Error("failed to publish order.placed", "order_id", order.ID, "error", err)
	}

	return order, nil
}

// validateItems performs a best-effort HTTP GET to the menu-service for each item.
// Failures are logged but never abort the order (resilience over strictness).
func (s *OrderService) validateItems(ctx context.Context, cart *model.Cart) {
	if s.menuURL == "" {
		return
	}
	for _, it := range cart.Items {
		url := fmt.Sprintf("%s/api/menu/items/%s", s.menuURL, it.ItemID)
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			s.logger.Warn("menu validation request build failed", "item_id", it.ItemID, "error", err)
			continue
		}
		resp, err := s.httpClient.Do(req)
		if err != nil {
			s.logger.Warn("menu validation skipped (unreachable)", "item_id", it.ItemID, "error", err)
			continue
		}
		_ = resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			s.logger.Warn("menu validation non-200", "item_id", it.ItemID, "status", resp.StatusCode)
		}
	}
}

// GetOrder returns a single order with items.
func (s *OrderService) GetOrder(ctx context.Context, id uuid.UUID) (*model.Order, error) {
	return s.repo.GetByID(ctx, id)
}

// ListOrders returns the customer's order history.
func (s *OrderService) ListOrders(ctx context.Context, customerID string) ([]model.Order, error) {
	return s.repo.ListByCustomer(ctx, customerID)
}

// HandleEvent is the broker.Handler for events this service consumes:
// payment.completed, payment.failed and delivery.updated.
func (s *OrderService) HandleEvent(routingKey string, body []byte) error {
	switch routingKey {
	case "payment.completed":
		return s.onPayment(body, model.StatusConfirmed)
	case "payment.failed":
		return s.onPayment(body, model.StatusPaymentFailed)
	case "delivery.updated":
		return s.onDelivery(body)
	default:
		s.logger.Warn("unhandled routing key", "routing_key", routingKey)
		return nil
	}
}

func (s *OrderService) onPayment(body []byte, status string) error {
	var e model.PaymentEvent
	if err := json.Unmarshal(body, &e); err != nil {
		return fmt.Errorf("unmarshal payment event: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := s.repo.UpdateStatusByOrderID(ctx, e.OrderID, status); err != nil {
		return fmt.Errorf("update order %s -> %s: %w", e.OrderID, status, err)
	}
	s.logger.Info("order status updated from payment", "order_id", e.OrderID, "status", status)
	return nil
}

func (s *OrderService) onDelivery(body []byte) error {
	var e model.DeliveryEvent
	if err := json.Unmarshal(body, &e); err != nil {
		return fmt.Errorf("unmarshal delivery event: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	// Delivery status maps directly onto order status (e.g. OUT_FOR_DELIVERY, DELIVERED).
	if err := s.repo.UpdateStatusByOrderID(ctx, e.OrderID, e.Status); err != nil {
		return fmt.Errorf("update order %s -> %s: %w", e.OrderID, e.Status, err)
	}
	s.logger.Info("order status updated from delivery", "order_id", e.OrderID, "status", e.Status)
	return nil
}
