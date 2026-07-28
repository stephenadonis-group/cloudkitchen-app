package repository

import (
	"context"
	"errors"
	"fmt"

	"github.com/cloudkitchen/user-service/internal/model"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotFound is returned when a requested row does not exist.
var ErrNotFound = errors.New("not found")

// UserRepository provides data access for users.profiles and users.addresses.
type UserRepository struct {
	pool *pgxpool.Pool
}

// NewUserRepository constructs a UserRepository.
func NewUserRepository(pool *pgxpool.Pool) *UserRepository {
	return &UserRepository{pool: pool}
}

// EnsureProfile creates an empty profile row for userID if none exists. Used by
// the user.registered event consumer; idempotent via ON CONFLICT.
func (r *UserRepository) EnsureProfile(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO profiles (user_id, full_name, phone) VALUES ($1, '', '')
		 ON CONFLICT (user_id) DO NOTHING`,
		userID,
	)
	if err != nil {
		return fmt.Errorf("ensure profile: %w", err)
	}
	return nil
}

// GetProfile loads a profile by user id.
func (r *UserRepository) GetProfile(ctx context.Context, userID uuid.UUID) (*model.Profile, error) {
	var p model.Profile
	err := r.pool.QueryRow(ctx,
		`SELECT user_id, full_name, phone FROM profiles WHERE user_id = $1`, userID,
	).Scan(&p.UserID, &p.FullName, &p.Phone)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get profile: %w", err)
	}
	return &p, nil
}

// UpsertProfile inserts or updates a profile.
func (r *UserRepository) UpsertProfile(ctx context.Context, p *model.Profile) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO profiles (user_id, full_name, phone) VALUES ($1, $2, $3)
		 ON CONFLICT (user_id) DO UPDATE SET full_name = EXCLUDED.full_name, phone = EXCLUDED.phone`,
		p.UserID, p.FullName, p.Phone,
	)
	if err != nil {
		return fmt.Errorf("upsert profile: %w", err)
	}
	return nil
}

// ListAddresses returns all addresses for a user.
func (r *UserRepository) ListAddresses(ctx context.Context, userID uuid.UUID) ([]model.Address, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, line1, city, pincode, is_default FROM addresses WHERE user_id = $1 ORDER BY is_default DESC`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("list addresses: %w", err)
	}
	defer rows.Close()

	var out []model.Address
	for rows.Next() {
		var a model.Address
		if err := rows.Scan(&a.ID, &a.UserID, &a.Line1, &a.City, &a.Pincode, &a.IsDefault); err != nil {
			return nil, fmt.Errorf("scan address: %w", err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// CreateAddress inserts a new address. If it is marked default, any previous
// default for the user is cleared within a transaction.
func (r *UserRepository) CreateAddress(ctx context.Context, a *model.Address) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if a.IsDefault {
		if _, err := tx.Exec(ctx, `UPDATE addresses SET is_default = false WHERE user_id = $1`, a.UserID); err != nil {
			return fmt.Errorf("clear default: %w", err)
		}
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO addresses (id, user_id, line1, city, pincode, is_default) VALUES ($1, $2, $3, $4, $5, $6)`,
		a.ID, a.UserID, a.Line1, a.City, a.Pincode, a.IsDefault,
	); err != nil {
		return fmt.Errorf("insert address: %w", err)
	}
	return tx.Commit(ctx)
}

// DeleteAddress removes an address owned by userID. Returns ErrNotFound if no
// row matched (wrong owner or missing id).
func (r *UserRepository) DeleteAddress(ctx context.Context, userID, addrID uuid.UUID) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM addresses WHERE id = $1 AND user_id = $2`, addrID, userID)
	if err != nil {
		return fmt.Errorf("delete address: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
