package service

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/cloudkitchen/order-service/internal/model"
	"github.com/cloudkitchen/order-service/pkg/cache"
)

// CartService manages the Redis-backed per-customer cart.
type CartService struct {
	cache *cache.Cache
}

// NewCartService constructs a CartService over a Redis cache.
func NewCartService(c *cache.Cache) *CartService {
	return &CartService{cache: c}
}

// cartKey builds the Redis key for a customer's cart.
func cartKey(customerID string) string { return "cart:" + customerID }

// Get returns the customer's cart (empty if none stored).
func (s *CartService) Get(ctx context.Context, customerID string) (*model.Cart, error) {
	raw, err := s.cache.Get(ctx, cartKey(customerID))
	if err != nil {
		return nil, fmt.Errorf("get cart: %w", err)
	}
	cart := &model.Cart{Items: []model.CartItem{}}
	if raw == "" {
		return cart, nil
	}
	if err := json.Unmarshal([]byte(raw), cart); err != nil {
		return nil, fmt.Errorf("unmarshal cart: %w", err)
	}
	return cart, nil
}

// AddOrUpdate inserts the item, or replaces quantity/price if item_id exists.
func (s *CartService) AddOrUpdate(ctx context.Context, customerID string, item model.CartItem) (*model.Cart, error) {
	cart, err := s.Get(ctx, customerID)
	if err != nil {
		return nil, err
	}
	found := false
	for i := range cart.Items {
		if cart.Items[i].ItemID == item.ItemID {
			cart.Items[i] = item
			found = true
			break
		}
	}
	if !found {
		cart.Items = append(cart.Items, item)
	}
	if err := s.save(ctx, customerID, cart); err != nil {
		return nil, err
	}
	return cart, nil
}

// RemoveItem deletes a single line by item_id.
func (s *CartService) RemoveItem(ctx context.Context, customerID, itemID string) (*model.Cart, error) {
	cart, err := s.Get(ctx, customerID)
	if err != nil {
		return nil, err
	}
	kept := cart.Items[:0]
	for _, it := range cart.Items {
		if it.ItemID != itemID {
			kept = append(kept, it)
		}
	}
	cart.Items = kept
	if err := s.save(ctx, customerID, cart); err != nil {
		return nil, err
	}
	return cart, nil
}

// Clear empties the cart by deleting the Redis key.
func (s *CartService) Clear(ctx context.Context, customerID string) error {
	if err := s.cache.Del(ctx, cartKey(customerID)); err != nil {
		return fmt.Errorf("clear cart: %w", err)
	}
	return nil
}

// save persists the cart JSON back to Redis.
func (s *CartService) save(ctx context.Context, customerID string, cart *model.Cart) error {
	b, err := json.Marshal(cart)
	if err != nil {
		return fmt.Errorf("marshal cart: %w", err)
	}
	if err := s.cache.Set(ctx, cartKey(customerID), string(b)); err != nil {
		return fmt.Errorf("save cart: %w", err)
	}
	return nil
}
