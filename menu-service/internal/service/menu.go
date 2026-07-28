// Package service holds menu-service business logic: category/item creation,
// aggregated menu reads with Redis caching, and item search.
package service

import (
	"context"
	"fmt"
	"time"

	"github.com/cloudkitchen/menu-service/internal/model"
	"github.com/cloudkitchen/menu-service/internal/repository"
	"github.com/cloudkitchen/menu-service/pkg/cache"
	"github.com/google/uuid"
)

// menuTTL is how long an aggregated menu is cached.
const menuTTL = 60 * time.Second

// searchTTL is how long a search result set is cached.
const searchTTL = 60 * time.Second

// MenuService coordinates the repository and Redis cache.
type MenuService struct {
	repo  *repository.MenuRepository
	cache *cache.Cache
}

// NewMenuService constructs a MenuService.
func NewMenuService(repo *repository.MenuRepository, c *cache.Cache) *MenuService {
	return &MenuService{repo: repo, cache: c}
}

// menuKey is the Redis key for a restaurant's aggregated menu.
func menuKey(restaurantID uuid.UUID) string { return "menu:" + restaurantID.String() }

// searchKey is the Redis key for a search query's results.
func searchKey(q string) string { return "menu:search:" + q }

// CreateCategory adds a category and invalidates the restaurant's cached menu.
func (s *MenuService) CreateCategory(ctx context.Context, restaurantID uuid.UUID, req model.CreateCategoryRequest) (*model.Category, error) {
	c := &model.Category{ID: uuid.New(), RestaurantID: restaurantID, Name: req.Name}
	if err := s.repo.CreateCategory(ctx, c); err != nil {
		return nil, err
	}
	_ = s.cache.Delete(ctx, menuKey(restaurantID))
	return c, nil
}

// CreateItem adds a menu item and invalidates the restaurant's cached menu.
func (s *MenuService) CreateItem(ctx context.Context, restaurantID uuid.UUID, req model.CreateItemRequest) (*model.MenuItem, error) {
	catID, err := uuid.Parse(req.CategoryID)
	if err != nil {
		return nil, fmt.Errorf("invalid category_id: %w", err)
	}
	available := true
	if req.Available != nil {
		available = *req.Available
	}
	i := &model.MenuItem{
		ID:           uuid.New(),
		RestaurantID: restaurantID,
		CategoryID:   catID,
		Name:         req.Name,
		Description:  req.Description,
		Price:        req.Price,
		Available:    available,
	}
	if err := s.repo.CreateItem(ctx, i); err != nil {
		return nil, err
	}
	_ = s.cache.Delete(ctx, menuKey(restaurantID))
	return i, nil
}

// GetMenu returns the aggregated menu, served from cache when warm and
// refreshed from the DB on a miss.
func (s *MenuService) GetMenu(ctx context.Context, restaurantID uuid.UUID) (*model.Menu, error) {
	key := menuKey(restaurantID)

	var cached model.Menu
	if err := s.cache.GetJSON(ctx, key, &cached); err == nil {
		return &cached, nil
	}

	cats, err := s.repo.ListCategories(ctx, restaurantID)
	if err != nil {
		return nil, err
	}
	items, err := s.repo.ListItems(ctx, restaurantID)
	if err != nil {
		return nil, err
	}
	m := &model.Menu{RestaurantID: restaurantID, Categories: cats, Items: items}

	_ = s.cache.SetJSON(ctx, key, m, menuTTL)
	return m, nil
}

// Search returns items matching q, served from cache when warm.
func (s *MenuService) Search(ctx context.Context, q string) ([]model.MenuItem, error) {
	key := searchKey(q)

	var cached []model.MenuItem
	if err := s.cache.GetJSON(ctx, key, &cached); err == nil {
		return cached, nil
	}

	items, err := s.repo.SearchItems(ctx, q)
	if err != nil {
		return nil, err
	}
	_ = s.cache.SetJSON(ctx, key, items, searchTTL)
	return items, nil
}
