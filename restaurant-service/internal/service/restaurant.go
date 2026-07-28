// Package service holds restaurant-service business logic: CRUD with ownership
// checks and event publishing.
package service

import (
	"context"
	"errors"
	"time"

	"github.com/cloudkitchen/restaurant-service/internal/model"
	"github.com/cloudkitchen/restaurant-service/internal/repository"
	"github.com/cloudkitchen/restaurant-service/pkg/broker"
	"github.com/google/uuid"
)

// ErrForbidden is returned when a caller tries to modify a restaurant they do
// not own (and is not an admin).
var ErrForbidden = errors.New("not allowed to modify this restaurant")

// RoleAdmin is the platform-wide admin role.
const RoleAdmin = "admin"

// RestaurantService coordinates the repository and broker.
type RestaurantService struct {
	repo   *repository.RestaurantRepository
	broker *broker.Broker
}

// NewRestaurantService constructs a RestaurantService.
func NewRestaurantService(repo *repository.RestaurantRepository, b *broker.Broker) *RestaurantService {
	return &RestaurantService{repo: repo, broker: b}
}

// Create persists a new restaurant owned by ownerID and publishes restaurant.created.
func (s *RestaurantService) Create(ctx context.Context, ownerID uuid.UUID, req model.CreateRestaurantRequest) (*model.Restaurant, error) {
	m := &model.Restaurant{
		ID:          uuid.New(),
		OwnerID:     ownerID,
		Name:        req.Name,
		Description: req.Description,
		Address:     req.Address,
		City:        req.City,
		Status:      "active",
		CreatedAt:   time.Now().UTC(),
	}
	if err := s.repo.Create(ctx, m); err != nil {
		return nil, err
	}
	if s.broker != nil {
		_ = s.broker.Publish("restaurant.created", model.RestaurantCreatedEvent{
			RestaurantID: m.ID.String(),
			OwnerID:      m.OwnerID.String(),
			Name:         m.Name,
			City:         m.City,
		})
	}
	return m, nil
}

// Get returns a restaurant by id.
func (s *RestaurantService) Get(ctx context.Context, id uuid.UUID) (*model.Restaurant, error) {
	return s.repo.GetByID(ctx, id)
}

// List returns restaurants optionally filtered by city.
func (s *RestaurantService) List(ctx context.Context, city string) ([]model.Restaurant, error) {
	return s.repo.List(ctx, city)
}

// Update modifies a restaurant. callerID must be the owner, or callerRole must
// be admin.
func (s *RestaurantService) Update(ctx context.Context, id, callerID uuid.UUID, callerRole string, req model.UpdateRestaurantRequest) (*model.Restaurant, error) {
	existing, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if existing.OwnerID != callerID && callerRole != RoleAdmin {
		return nil, ErrForbidden
	}

	existing.Name = req.Name
	existing.Description = req.Description
	existing.Address = req.Address
	existing.City = req.City
	if req.Status != "" {
		existing.Status = req.Status
	}
	if err := s.repo.Update(ctx, existing); err != nil {
		return nil, err
	}
	return existing, nil
}
