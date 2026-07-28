// Package model defines the domain types and DTOs for menu-service.
package model

import "github.com/google/uuid"

// Category is a row in menu.categories.
type Category struct {
	ID           uuid.UUID `json:"id"`
	RestaurantID uuid.UUID `json:"restaurant_id"`
	Name         string    `json:"name"`
}

// MenuItem is a row in menu.menu_items.
type MenuItem struct {
	ID           uuid.UUID `json:"id"`
	RestaurantID uuid.UUID `json:"restaurant_id"`
	CategoryID   uuid.UUID `json:"category_id"`
	Name         string    `json:"name"`
	Description  string    `json:"description"`
	Price        float64   `json:"price"`
	Available    bool      `json:"available"`
}

// CreateCategoryRequest is the body for POST /api/restaurants/:rid/categories.
type CreateCategoryRequest struct {
	Name string `json:"name" binding:"required"`
}

// CreateItemRequest is the body for POST /api/restaurants/:rid/items.
type CreateItemRequest struct {
	CategoryID  string  `json:"category_id" binding:"required,uuid"`
	Name        string  `json:"name" binding:"required"`
	Description string  `json:"description"`
	Price       float64 `json:"price" binding:"required,gt=0"`
	Available   *bool   `json:"available"`
}

// Menu is the aggregated public view returned by GET /api/restaurants/:rid/menu.
type Menu struct {
	RestaurantID uuid.UUID  `json:"restaurant_id"`
	Categories   []Category `json:"categories"`
	Items        []MenuItem `json:"items"`
}
