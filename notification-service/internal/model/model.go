// Package model holds the domain types and event payloads for the
// notification-service.
package model

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// Notification channel + type values.
const (
	ChannelEmail = "email"

	TypeOrderPlaced      = "order.placed"
	TypePaymentCompleted = "payment.completed"
	TypeDeliveryUpdated  = "delivery.updated"
)

// Notification is a persisted notification record.
type Notification struct {
	ID      uuid.UUID       `json:"id"`
	UserID  string          `json:"user_id"`
	Channel string          `json:"channel"`
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
	SentAt  time.Time       `json:"sent_at"`
}

// OrderPlacedEvent is consumed on "order.placed".
type OrderPlacedEvent struct {
	OrderID      string  `json:"order_id"`
	CustomerID   string  `json:"customer_id"`
	RestaurantID string  `json:"restaurant_id"`
	Total        float64 `json:"total"`
}

// PaymentEvent is consumed on "payment.completed".
type PaymentEvent struct {
	OrderID   string  `json:"order_id"`
	PaymentID string  `json:"payment_id"`
	Status    string  `json:"status"`
	Amount    float64 `json:"amount"`
}

// DeliveryEvent is consumed on "delivery.updated".
type DeliveryEvent struct {
	OrderID    string `json:"order_id"`
	DeliveryID string `json:"delivery_id"`
	Status     string `json:"status"`
	AgentID    string `json:"agent_id"`
}
