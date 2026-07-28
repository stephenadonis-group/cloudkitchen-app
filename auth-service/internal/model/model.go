// Package model defines the domain types and DTOs for auth-service.
package model

import (
	"time"

	"github.com/google/uuid"
)

// User is a row in the auth.users table.
type User struct {
	ID           uuid.UUID `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	Role         string    `json:"role"`
	CreatedAt    time.Time `json:"created_at"`
}

// RegisterRequest is the body for POST /api/auth/register.
type RegisterRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
	Role     string `json:"role" binding:"required,oneof=customer restaurant-admin delivery-agent admin"`
}

// LoginRequest is the body for POST /api/auth/login.
type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

// LoginResponse carries the issued JWT.
type LoginResponse struct {
	Token string `json:"token"`
}

// UserRegisteredEvent is published on the "user.registered" routing key.
type UserRegisteredEvent struct {
	UserID string `json:"user_id"`
	Email  string `json:"email"`
	Role   string `json:"role"`
}
