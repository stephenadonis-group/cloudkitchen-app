package repository

import (
	"context"
	"fmt"

	"github.com/cloudkitchen/menu-service/internal/model"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// MenuRepository provides data access for menu.categories and menu.menu_items.
type MenuRepository struct {
	pool *pgxpool.Pool
}

// NewMenuRepository constructs a MenuRepository.
func NewMenuRepository(pool *pgxpool.Pool) *MenuRepository {
	return &MenuRepository{pool: pool}
}

// CreateCategory inserts a new category.
func (r *MenuRepository) CreateCategory(ctx context.Context, c *model.Category) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO categories (id, restaurant_id, name) VALUES ($1, $2, $3)`,
		c.ID, c.RestaurantID, c.Name,
	)
	if err != nil {
		return fmt.Errorf("insert category: %w", err)
	}
	return nil
}

// CreateItem inserts a new menu item.
func (r *MenuRepository) CreateItem(ctx context.Context, i *model.MenuItem) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO menu_items (id, restaurant_id, category_id, name, description, price, available)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		i.ID, i.RestaurantID, i.CategoryID, i.Name, i.Description, i.Price, i.Available,
	)
	if err != nil {
		return fmt.Errorf("insert menu item: %w", err)
	}
	return nil
}

// ListCategories returns all categories for a restaurant.
func (r *MenuRepository) ListCategories(ctx context.Context, restaurantID uuid.UUID) ([]model.Category, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, restaurant_id, name FROM categories WHERE restaurant_id = $1 ORDER BY name`,
		restaurantID,
	)
	if err != nil {
		return nil, fmt.Errorf("list categories: %w", err)
	}
	defer rows.Close()

	var out []model.Category
	for rows.Next() {
		var c model.Category
		if err := rows.Scan(&c.ID, &c.RestaurantID, &c.Name); err != nil {
			return nil, fmt.Errorf("scan category: %w", err)
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// ListItems returns all menu items for a restaurant.
func (r *MenuRepository) ListItems(ctx context.Context, restaurantID uuid.UUID) ([]model.MenuItem, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, restaurant_id, category_id, name, description, price, available
		 FROM menu_items WHERE restaurant_id = $1 ORDER BY name`,
		restaurantID,
	)
	if err != nil {
		return nil, fmt.Errorf("list items: %w", err)
	}
	defer rows.Close()

	return scanItems(rows)
}

// SearchItems returns available items whose name matches the query via ILIKE.
func (r *MenuRepository) SearchItems(ctx context.Context, query string) ([]model.MenuItem, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, restaurant_id, category_id, name, description, price, available
		 FROM menu_items WHERE name ILIKE $1 AND available = true ORDER BY name LIMIT 100`,
		"%"+query+"%",
	)
	if err != nil {
		return nil, fmt.Errorf("search items: %w", err)
	}
	defer rows.Close()

	return scanItems(rows)
}

// scanItems is a shared helper to materialize MenuItem rows.
func scanItems(rows interface {
	Next() bool
	Scan(...any) error
	Err() error
}) ([]model.MenuItem, error) {
	var out []model.MenuItem
	for rows.Next() {
		var i model.MenuItem
		if err := rows.Scan(&i.ID, &i.RestaurantID, &i.CategoryID, &i.Name, &i.Description, &i.Price, &i.Available); err != nil {
			return nil, fmt.Errorf("scan item: %w", err)
		}
		out = append(out, i)
	}
	return out, rows.Err()
}
