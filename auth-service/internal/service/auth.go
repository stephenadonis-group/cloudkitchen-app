// Package service holds the auth-service business logic: registration, login,
// JWT issuance, and event publishing.
package service

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/cloudkitchen/auth-service/internal/middleware"
	"github.com/cloudkitchen/auth-service/internal/model"
	"github.com/cloudkitchen/auth-service/internal/repository"
	"github.com/cloudkitchen/auth-service/pkg/broker"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

// ErrInvalidCredentials is returned when login fails authentication.
var ErrInvalidCredentials = errors.New("invalid email or password")

// ErrEmailTaken is returned when registering an already-used email.
var ErrEmailTaken = errors.New("email already registered")

// AuthService coordinates the user repository, JWT signing, and the broker.
type AuthService struct {
	repo      *repository.UserRepository
	broker    *broker.Broker
	jwtSecret string
	jwtExpiry time.Duration
}

// NewAuthService constructs an AuthService.
func NewAuthService(repo *repository.UserRepository, b *broker.Broker, secret string, expiry time.Duration) *AuthService {
	return &AuthService{repo: repo, broker: b, jwtSecret: secret, jwtExpiry: expiry}
}

// Register hashes the password, persists the user, and publishes user.registered.
func (s *AuthService) Register(ctx context.Context, req model.RegisterRequest) (*model.User, error) {
	if existing, err := s.repo.GetByEmail(ctx, req.Email); err == nil && existing != nil {
		return nil, ErrEmailTaken
	} else if err != nil && !errors.Is(err, repository.ErrNotFound) {
		return nil, err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hash password: %w", err)
	}

	u := &model.User{
		ID:           uuid.New(),
		Email:        req.Email,
		PasswordHash: string(hash),
		Role:         req.Role,
		CreatedAt:    time.Now().UTC(),
	}
	if err := s.repo.Create(ctx, u); err != nil {
		return nil, err
	}

	// Publish the event; failure to publish should not roll back the user, but
	// is surfaced to the caller for logging.
	if s.broker != nil {
		_ = s.broker.Publish("user.registered", model.UserRegisteredEvent{
			UserID: u.ID.String(),
			Email:  u.Email,
			Role:   u.Role,
		})
	}
	return u, nil
}

// Login verifies credentials and returns a signed JWT.
func (s *AuthService) Login(ctx context.Context, req model.LoginRequest) (string, error) {
	u, err := s.repo.GetByEmail(ctx, req.Email)
	if errors.Is(err, repository.ErrNotFound) {
		return "", ErrInvalidCredentials
	}
	if err != nil {
		return "", err
	}
	if err := bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(req.Password)); err != nil {
		return "", ErrInvalidCredentials
	}
	return s.issueToken(u)
}

// issueToken builds and signs a JWT for the given user.
func (s *AuthService) issueToken(u *model.User) (string, error) {
	now := time.Now()
	claims := middleware.Claims{
		Email: u.Email,
		Role:  u.Role,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   u.ID.String(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.jwtExpiry)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(s.jwtSecret))
	if err != nil {
		return "", fmt.Errorf("sign token: %w", err)
	}
	return signed, nil
}
