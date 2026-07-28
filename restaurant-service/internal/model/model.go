// Package model defines the domain types and DTOs for restaurant-service.
package model

import (
	"time"

	"github.com/google/uuid"
)

// Restaurant is a row in restaurants.restaurants.
type Restaurant struct {
	ID          uuid.UUID `json:"id"`
	OwnerID     uuid.UUID `json:"owner_id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	Address     string    `json:"address"`
	City        string    `json:"city"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
}

// CreateRestaurantRequest is the body for POST /api/restaurants.
type CreateRestaurantRequest struct {
	Name        string `json:"name" binding:"required"`
	Description string `json:"description"`
	Address     string `json:"address" binding:"required"`
	City        string `json:"city" binding:"required"`
}

// UpdateRestaurantRequest is the body for PUT /api/restaurants/:id.
type UpdateRestaurantRequest struct {
	Name        string `json:"name" binding:"required"`
	Description string `json:"description"`
	Address     string `json:"address" binding:"required"`
	City        string `json:"city" binding:"required"`
	Status      string `json:"status" binding:"omitempty,oneof=active inactive"`
}

// RestaurantCreatedEvent is published on the "restaurant.created" routing key.
type RestaurantCreatedEvent struct {
	RestaurantID string `json:"restaurant_id"`
	OwnerID      string `json:"owner_id"`
	Name         string `json:"name"`
	City         string `json:"city"`
}
