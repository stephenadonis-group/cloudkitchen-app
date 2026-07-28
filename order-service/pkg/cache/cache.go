// Package cache wraps a go-redis client used by the order-service to persist the
// per-customer cart at key "cart:<customer_id>" as a JSON document.
package cache

import (
	"context"
	"fmt"

	"github.com/redis/go-redis/v9"
)

// Cache is a thin wrapper over *redis.Client.
type Cache struct {
	rdb *redis.Client
}

// New constructs a Redis-backed cache and verifies connectivity with a PING.
func New(addr, password string) (*Cache, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: password,
		DB:       0,
	})
	ctx, cancel := context.WithTimeout(context.Background(), 5e9)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("redis ping: %w", err)
	}
	return &Cache{rdb: rdb}, nil
}

// Get returns the raw JSON value stored at key, or ("", nil) if absent.
func (c *Cache) Get(ctx context.Context, key string) (string, error) {
	v, err := c.rdb.Get(ctx, key).Result()
	if err == redis.Nil {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return v, nil
}

// Set stores the raw JSON value at key (no expiry; cart lives until checkout).
func (c *Cache) Set(ctx context.Context, key, value string) error {
	return c.rdb.Set(ctx, key, value, 0).Err()
}

// Del removes the key.
func (c *Cache) Del(ctx context.Context, key string) error {
	return c.rdb.Del(ctx, key).Err()
}

// Ping checks connectivity (used by readiness probe).
func (c *Cache) Ping(ctx context.Context) error {
	return c.rdb.Ping(ctx).Err()
}

// Close releases the underlying connection pool.
func (c *Cache) Close() error {
	return c.rdb.Close()
}
