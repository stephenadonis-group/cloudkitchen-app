// Package model holds the domain types and event payloads for the order-service.
package model

import (
	"time"

	"github.com/google/uuid"
)

// Order status lifecycle values.
const (
	StatusPending        = "PENDING"
	StatusConfirmed      = "CONFIRMED"
	StatusPaymentFailed  = "PAYMENT_FAILED"
	StatusOutForDelivery = "OUT_FOR_DELIVERY"
	StatusDelivered      = "DELIVERED"
)

// CartItem is a single line in a customer's Redis-backed cart.
type CartItem struct {
	ItemID string  `json:"item_id" binding:"required"`
	Name   string  `json:"name" binding:"required"`
	Qty    int     `json:"qty" binding:"required,gt=0"`
	Price  float64 `json:"price" binding:"required,gte=0"`
}

// Cart is the JSON document stored at key cart:<customer_id>.
type Cart struct {
	Items []CartItem `json:"items"`
}

// Total sums the line totals of the cart.
func (c *Cart) Total() float64 {
	var t float64
	for _, it := range c.Items {
		t += it.Price * float64(it.Qty)
	}
	return t
}

// Order is a persisted order header.
type Order struct {
	ID           uuid.UUID   `json:"id"`
	CustomerID   string      `json:"customer_id"`
	RestaurantID string      `json:"restaurant_id"`
	Status       string      `json:"status"`
	Total        float64     `json:"total"`
	CreatedAt    time.Time   `json:"created_at"`
	Items        []OrderItem `json:"items,omitempty"`
}

// OrderItem is a persisted line item belonging to an Order.
type OrderItem struct {
	ID      uuid.UUID `json:"id"`
	OrderID uuid.UUID `json:"order_id"`
	ItemID  string    `json:"item_id"`
	Name    string    `json:"name"`
	Qty     int       `json:"qty"`
	Price   float64   `json:"price"`
}

// CreateOrderRequest is the body for POST /api/orders.
type CreateOrderRequest struct {
	RestaurantID string `json:"restaurant_id" binding:"required"`
}

// --- Event payloads (cloudkitchen.events) ---

// OrderPlacedEvent is published on "order.placed".
type OrderPlacedEvent struct {
	OrderID      string  `json:"order_id"`
	CustomerID   string  `json:"customer_id"`
	RestaurantID string  `json:"restaurant_id"`
	Total        float64 `json:"total"`
}

// PaymentEvent is consumed on "payment.completed" / "payment.failed".
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
