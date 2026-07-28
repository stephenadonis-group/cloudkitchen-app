// Package repository contains all persistence logic for the order-service:
// the pgx connection pool, the embedded idempotent migration runner, and the
// data-access methods for orders and order_items.
package repository

import (
	"context"
	"fmt"
	"io/fs"
	"sort"

	"github.com/jackc/pgx/v5/pgxpool"
)

// NewPool creates a pgxpool from the given DSN and verifies connectivity.
func NewPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("pgxpool new: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("pgxpool ping: %w", err)
	}
	return pool, nil
}

// Migrate ensures the schema exists, sets the search_path and applies every
// *.sql file from the provided filesystem in lexical order. The migrations FS is
// embedded at the module root and passed in by main. Migrations must be idempotent.
func Migrate(ctx context.Context, pool *pgxpool.Pool, schema string, migrations fs.FS) error {
	if _, err := pool.Exec(ctx, fmt.Sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema)); err != nil {
		return fmt.Errorf("create schema: %w", err)
	}
	if _, err := pool.Exec(ctx, fmt.Sprintf("SET search_path TO %s", schema)); err != nil {
		return fmt.Errorf("set search_path: %w", err)
	}

	entries, err := fs.ReadDir(migrations, ".")
	if err != nil {
		return fmt.Errorf("read migrations dir: %w", err)
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	for _, name := range names {
		sqlBytes, err := fs.ReadFile(migrations, name)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", name, err)
		}
		// Ensure objects are created in the service schema regardless of session default.
		stmt := fmt.Sprintf("SET search_path TO %s;\n%s", schema, string(sqlBytes))
		if _, err := pool.Exec(ctx, stmt); err != nil {
			return fmt.Errorf("apply migration %s: %w", name, err)
		}
	}
	return nil
}
