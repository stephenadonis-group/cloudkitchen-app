// Package model defines the domain types and DTOs for user-service.
package model

import "github.com/google/uuid"

// Profile is a row in users.profiles.
type Profile struct {
	UserID   uuid.UUID `json:"user_id"`
	FullName string    `json:"full_name"`
	Phone    string    `json:"phone"`
}

// Address is a row in users.addresses.
type Address struct {
	ID        uuid.UUID `json:"id"`
	UserID    uuid.UUID `json:"user_id"`
	Line1     string    `json:"line1"`
	City      string    `json:"city"`
	Pincode   string    `json:"pincode"`
	IsDefault bool      `json:"is_default"`
}

// UpdateProfileRequest is the body for PUT /api/users/me/profile.
type UpdateProfileRequest struct {
	FullName string `json:"full_name" binding:"required"`
	Phone    string `json:"phone"`
}

// CreateAddressRequest is the body for POST /api/users/me/addresses.
type CreateAddressRequest struct {
	Line1     string `json:"line1" binding:"required"`
	City      string `json:"city" binding:"required"`
	Pincode   string `json:"pincode" binding:"required"`
	IsDefault bool   `json:"is_default"`
}

// UserRegisteredEvent is the payload consumed from "user.registered".
type UserRegisteredEvent struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
	Role   string `json:"role"`
}
