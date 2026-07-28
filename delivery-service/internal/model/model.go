// Package model holds the domain types and event payloads for the delivery-service.
package model

import (
	"time"

	"github.com/google/uuid"
)

// Delivery status lifecycle values.
const (
	StatusAssigned       = "ASSIGNED"
	StatusPickedUp       = "PICKED_UP"
	StatusOutForDelivery = "OUT_FOR_DELIVERY"
	StatusDelivered      = "DELIVERED"
)

// Agent is a delivery agent who can be assigned to deliveries.
type Agent struct {
	ID        uuid.UUID `json:"id"`
	Name      string    `json:"name"`
	Phone     string    `json:"phone"`
	Available bool      `json:"available"`
}

// Delivery is a persisted delivery record for an order.
type Delivery struct {
	ID        uuid.UUID  `json:"id"`
	OrderID   string     `json:"order_id"`
	AgentID   *uuid.UUID `json:"agent_id,omitempty"`
	Status    string     `json:"status"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
}

// UpdateStatusRequest is the body for PUT /api/deliveries/:id/status.
type UpdateStatusRequest struct {
	Status string `json:"status" binding:"required"`
}

// PaymentEvent is consumed on "payment.completed".
type PaymentEvent struct {
	OrderID   string  `json:"order_id"`
	PaymentID string  `json:"payment_id"`
	Status    string  `json:"status"`
	Amount    float64 `json:"amount"`
}

// DeliveryEvent is published on "delivery.updated".
type DeliveryEvent struct {
	OrderID    string `json:"order_id"`
	DeliveryID string `json:"delivery_id"`
	Status     string `json:"status"`
	AgentID    string `json:"agent_id"`
}

// ValidStatus reports whether s is a settable delivery status via the API.
func ValidStatus(s string) bool {
	switch s {
	case StatusPickedUp, StatusOutForDelivery, StatusDelivered:
		return true
	default:
		return false
	}
}
