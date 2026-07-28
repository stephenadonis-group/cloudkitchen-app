// Package service holds user-service business logic: profile/address management
// and the user.registered event consumer.
package service

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/cloudkitchen/user-service/internal/model"
	"github.com/cloudkitchen/user-service/internal/repository"
	"github.com/google/uuid"
)

// UserService coordinates the repository for profiles and addresses.
type UserService struct {
	repo *repository.UserRepository
}

// NewUserService constructs a UserService.
func NewUserService(repo *repository.UserRepository) *UserService {
	return &UserService{repo: repo}
}

// HandleUserRegistered is the broker handler for "user.registered". It creates an
// empty profile for the new user.
func (s *UserService) HandleUserRegistered(routingKey string, body []byte) error {
	var ev model.UserRegisteredEvent
	if err := json.Unmarshal(body, &ev); err != nil {
		return fmt.Errorf("unmarshal user.registered: %w", err)
	}
	uid, err := uuid.Parse(ev.UserID)
	if err != nil {
		return fmt.Errorf("parse user id: %w", err)
	}
	return s.repo.EnsureProfile(context.Background(), uid)
}

// GetProfile returns a user's profile.
func (s *UserService) GetProfile(ctx context.Context, userID uuid.UUID) (*model.Profile, error) {
	return s.repo.GetProfile(ctx, userID)
}

// UpdateProfile upserts a user's profile fields.
func (s *UserService) UpdateProfile(ctx context.Context, userID uuid.UUID, req model.UpdateProfileRequest) (*model.Profile, error) {
	p := &model.Profile{UserID: userID, FullName: req.FullName, Phone: req.Phone}
	if err := s.repo.UpsertProfile(ctx, p); err != nil {
		return nil, err
	}
	return p, nil
}

// ListAddresses returns a user's addresses.
func (s *UserService) ListAddresses(ctx context.Context, userID uuid.UUID) ([]model.Address, error) {
	return s.repo.ListAddresses(ctx, userID)
}

// CreateAddress adds a new address for a user.
func (s *UserService) CreateAddress(ctx context.Context, userID uuid.UUID, req model.CreateAddressRequest) (*model.Address, error) {
	a := &model.Address{
		ID:        uuid.New(),
		UserID:    userID,
		Line1:     req.Line1,
		City:      req.City,
		Pincode:   req.Pincode,
		IsDefault: req.IsDefault,
	}
	if err := s.repo.CreateAddress(ctx, a); err != nil {
		return nil, err
	}
	return a, nil
}

// DeleteAddress removes a user's address.
func (s *UserService) DeleteAddress(ctx context.Context, userID, addrID uuid.UUID) error {
	return s.repo.DeleteAddress(ctx, userID, addrID)
}
