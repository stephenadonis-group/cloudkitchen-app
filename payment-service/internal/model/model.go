// Package model holds the domain types and event payloads for the payment-service.
package model

import (
	"time"

	"github.com/google/uuid"
)

// Payment status values.
const (
	StatusSuccess = "SUCCESS"
	StatusFailed  = "FAILED"
)

// Payment is a persisted payment record.
type Payment struct {
	ID        uuid.UUID `json:"id"`
	OrderID   string    `json:"order_id"`
	Amount    float64   `json:"amount"`
	Method    string    `json:"method"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

// OrderPlacedEvent is consumed on "order.placed".
type OrderPlacedEvent struct {
	OrderID      string  `json:"order_id"`
	CustomerID   string  `json:"customer_id"`
	RestaurantID string  `json:"restaurant_id"`
	Total        float64 `json:"total"`
}

// PaymentEvent is published on "payment.completed" / "payment.failed".
type PaymentEvent struct {
	OrderID   string  `json:"order_id"`
	PaymentID string  `json:"payment_id"`
	Status    string  `json:"status"`
	Amount    float64 `json:"amount"`
}
