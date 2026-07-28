// Package repository handles all persistence. db.go owns connection pooling and
// the embedded-migration runner; user.go contains the users data access.
package repository

import (
	"context"
	"embed"
	"fmt"
	"path"
	"sort"

	"github.com/jackc/pgx/v5/pgxpool"
)

// The migration SQL files are embedded by the top-level `migrations` package
// (via go:embed) and passed into RunMigrations below, keeping this package
// decoupled from the embed directive.

// Connect creates a pgxpool, ensures the schema exists, sets the search_path,
// and is ready for migrations to run.
func Connect(ctx context.Context, dsn, schema string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("create pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping db: %w", err)
	}
	// Ensure the per-service schema exists before anything else.
	if _, err := pool.Exec(ctx, fmt.Sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema)); err != nil {
		pool.Close()
		return nil, fmt.Errorf("create schema %s: %w", schema, err)
	}
	return pool, nil
}

// RunMigrations executes every *.sql file in fsys (sorted by name) inside the
// given schema. All migrations are expected to be idempotent.
func RunMigrations(ctx context.Context, pool *pgxpool.Pool, schema string, fsys embed.FS, dir string) error {
	entries, err := fsys.ReadDir(dir)
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
		content, err := fsys.ReadFile(path.Join(dir, name))
		if err != nil {
			return fmt.Errorf("read migration %s: %w", name, err)
		}
		// Pin the search_path for this statement batch so unqualified DDL lands
		// in the service schema.
		stmt := fmt.Sprintf("SET search_path TO %s;\n%s", schema, string(content))
		if _, err := pool.Exec(ctx, stmt); err != nil {
			return fmt.Errorf("exec migration %s: %w", name, err)
		}
	}
	return nil
}
