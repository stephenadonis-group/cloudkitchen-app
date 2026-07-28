// Package cache wraps a Redis client with simple JSON get/set/delete helpers
// used by menu-service to cache menu and search results.
package cache

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/redis/go-redis/v9"
)

// ErrMiss indicates the key was not present in the cache.
var ErrMiss = errors.New("cache miss")

// Cache is a thin Redis wrapper. A nil *Cache is safe and behaves as a no-op
// (always misses), so the service still works when Redis is unavailable.
type Cache struct {
	rdb *redis.Client
}

// New connects to Redis at addr. It pings to verify connectivity; on failure it
// returns the error so the caller can decide to run without caching.
func New(addr, password string) (*Cache, error) {
	rdb := redis.NewClient(&redis.Options{Addr: addr, Password: password})
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, err
	}
	return &Cache{rdb: rdb}, nil
}

// GetJSON unmarshals the value at key into dest. Returns ErrMiss if absent or if
// the cache is nil/disabled.
func (c *Cache) GetJSON(ctx context.Context, key string, dest any) error {
	if c == nil || c.rdb == nil {
		return ErrMiss
	}
	b, err := c.rdb.Get(ctx, key).Bytes()
	if errors.Is(err, redis.Nil) {
		return ErrMiss
	}
	if err != nil {
		return err
	}
	return json.Unmarshal(b, dest)
}

// SetJSON marshals value and stores it at key with the given TTL. No-op if disabled.
func (c *Cache) SetJSON(ctx context.Context, key string, value any, ttl time.Duration) error {
	if c == nil || c.rdb == nil {
		return nil
	}
	b, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return c.rdb.Set(ctx, key, b, ttl).Err()
}

// Delete removes one or more keys. No-op if disabled.
func (c *Cache) Delete(ctx context.Context, keys ...string) error {
	if c == nil || c.rdb == nil || len(keys) == 0 {
		return nil
	}
	return c.rdb.Del(ctx, keys...).Err()
}

// Close releases the Redis connection.
func (c *Cache) Close() {
	if c != nil && c.rdb != nil {
		_ = c.rdb.Close()
	}
}
