package repository

import (
	"context"
	"errors"
	"fmt"

	"github.com/cloudkitchen/restaurant-service/internal/model"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when a restaurant row does not exist.
var ErrNotFound = errors.New("restaurant not found")

// RestaurantRepository provides data access for restaurants.restaurants.
type RestaurantRepository struct {
	pool *pgxpool.Pool
}

// NewRestaurantRepository constructs a RestaurantRepository.
func NewRestaurantRepository(pool *pgxpool.Pool) *RestaurantRepository {
	return &RestaurantRepository{pool: pool}
}

// Create inserts a new restaurant.
func (r *RestaurantRepository) Create(ctx context.Context, m *model.Restaurant) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO restaurants (id, owner_id, name, description, address, city, status, created_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		m.ID, m.OwnerID, m.Name, m.Description, m.Address, m.City, m.Status, m.CreatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert restaurant: %w", err)
	}
	return nil
}

// GetByID loads a restaurant by id.
func (r *RestaurantRepository) GetByID(ctx context.Context, id uuid.UUID) (*model.Restaurant, error) {
	var m model.Restaurant
	err := r.pool.QueryRow(ctx,
		`SELECT id, owner_id, name, description, address, city, status, created_at
		 FROM restaurants WHERE id = $1`, id,
	).Scan(&m.ID, &m.OwnerID, &m.Name, &m.Description, &m.Address, &m.City, &m.Status, &m.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get restaurant: %w", err)
	}
	return &m, nil
}

// List returns all restaurants, optionally filtered by city (empty = no filter).
func (r *RestaurantRepository) List(ctx context.Context, city string) ([]model.Restaurant, error) {
	var (
		rows pgx.Rows
		err  error
	)
	if city == "" {
		rows, err = r.pool.Query(ctx,
			`SELECT id, owner_id, name, description, address, city, status, created_at
			 FROM restaurants ORDER BY created_at DESC`)
	} else {
		rows, err = r.pool.Query(ctx,
			`SELECT id, owner_id, name, description, address, city, status, created_at
			 FROM restaurants WHERE city = $1 ORDER BY created_at DESC`, city)
	}
	if err != nil {
		return nil, fmt.Errorf("list restaurants: %w", err)
	}
	defer rows.Close()

	var out []model.Restaurant
	for rows.Next() {
		var m model.Restaurant
		if err := rows.Scan(&m.ID, &m.OwnerID, &m.Name, &m.Description, &m.Address, &m.City, &m.Status, &m.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan restaurant: %w", err)
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// Update modifies an existing restaurant's mutable fields.
func (r *RestaurantRepository) Update(ctx context.Context, m *model.Restaurant) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE restaurants SET name = $2, description = $3, address = $4, city = $5, status = $6
		 WHERE id = $1`,
		m.ID, m.Name, m.Description, m.Address, m.City, m.Status,
	)
	if err != nil {
		return fmt.Errorf("update restaurant: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
