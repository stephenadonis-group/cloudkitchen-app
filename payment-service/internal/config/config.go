// Package config loads runtime configuration from environment variables for the
// payment-service.
package config

import (
	"fmt"
	"os"
	"time"
)

// Config holds every environment-driven setting the payment-service needs.
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

	NATSURL string

	JWTSecret string
	JWTExpiry time.Duration
}

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
		ServiceName: getenv("SERVICE_NAME", "payment-service"),
		Port:        getenv("PORT", "8080"),
		LogLevel:    getenv("LOG_LEVEL", "info"),
		DBHost:      getenv("DB_HOST", "localhost"),
		DBPort:      getenv("DB_PORT", "5432"),
		DBUser:      getenv("DB_USER", "postgres"),
		DBPassword:  getenv("DB_PASSWORD", "postgres"),
		DBName:      getenv("DB_NAME", "cloudkitchen"),
		DBSchema:    getenv("DB_SCHEMA", "payments"),
		NATSURL: getenv("NATS_URL", "nats://localhost:4222"),
		JWTSecret:   getenv("JWT_SECRET", "change-me-in-production"),
		JWTExpiry:   expiry,
	}
}

// DSN builds the pgx connection string with search_path set to the service schema.
func (c *Config) DSN() string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=disable&search_path=%s",
		c.DBUser, c.DBPassword, c.DBHost, c.DBPort, c.DBName, c.DBSchema,
	)
}
