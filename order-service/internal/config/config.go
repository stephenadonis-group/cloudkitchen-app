// Package config loads all runtime configuration from environment variables
// into a single typed Config struct that the rest of the service depends on.
package config

import (
	"fmt"
	"os"
	"time"
)

// Config holds every environment-driven setting the order-service needs.
type Config struct {
	ServiceName string
	Port        string
	LogLevel    string

	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	DBSchema   string

	RedisAddr     string
	RedisPassword string

	NATSURL string

	JWTSecret string
	JWTExpiry time.Duration

	// Downstream service URLs used for best-effort validation.
	MenuServiceURL       string
	RestaurantServiceURL string
}

// getenv returns the env var value or a fallback default.
func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// Load reads the environment into a Config, applying sensible defaults.
func Load() *Config {
	expiry, err := time.ParseDuration(getenv("JWT_EXPIRY", "24h"))
	if err != nil {
		expiry = 24 * time.Hour
	}
	return &Config{
		ServiceName:          getenv("SERVICE_NAME", "order-service"),
		Port:                 getenv("PORT", "8080"),
		LogLevel:             getenv("LOG_LEVEL", "info"),
		DBHost:               getenv("DB_HOST", "localhost"),
		DBPort:               getenv("DB_PORT", "5432"),
		DBUser:               getenv("DB_USER", "postgres"),
		DBPassword:           getenv("DB_PASSWORD", "postgres"),
		DBName:               getenv("DB_NAME", "cloudkitchen"),
		DBSchema:             getenv("DB_SCHEMA", "orders"),
		RedisAddr:            getenv("REDIS_ADDR", "localhost:6379"),
		RedisPassword:        getenv("REDIS_PASSWORD", ""),
		NATSURL:          getenv("NATS_URL", "nats://localhost:4222"),
		JWTSecret:            getenv("JWT_SECRET", "change-me-in-production"),
		JWTExpiry:            expiry,
		MenuServiceURL:       getenv("MENU_SERVICE_URL", "http://localhost:8081"),
		RestaurantServiceURL: getenv("RESTAURANT_SERVICE_URL", "http://localhost:8082"),
	}
}

// DSN builds the pgx connection string. search_path is set to the service
// schema so all unqualified table references resolve to it.
func (c *Config) DSN() string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=disable&search_path=%s",
		c.DBUser, c.DBPassword, c.DBHost, c.DBPort, c.DBName, c.DBSchema,
	)
}
