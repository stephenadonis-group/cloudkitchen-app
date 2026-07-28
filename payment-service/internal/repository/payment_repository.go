package repository

import (
	"context"
	"fmt"

	"github.com/cloudkitchen/payment-service/internal/model"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PaymentRepository persists payment records.
type PaymentRepository struct {
	pool *pgxpool.Pool
}

// NewPaymentRepository wires the repository to a pgx pool.
func NewPaymentRepository(pool *pgxpool.Pool) *PaymentRepository {
	return &PaymentRepository{pool: pool}
}

// Create inserts a payment row.
func (r *PaymentRepository) Create(ctx context.Context, p *model.Payment) error {
	if _, err := r.pool.Exec(ctx,
		`INSERT INTO payments (id, order_id, amount, method, status, created_at)
		 VALUES ($1,$2,$3,$4,$5,$6)`,
		p.ID, p.OrderID, p.Amount, p.Method, p.Status, p.CreatedAt,
	); err != nil {
		return fmt.Errorf("insert payment: %w", err)
	}
	return nil
}

// GetByOrderID returns the most recent payment for an order, or pgx.ErrNoRows.
func (r *PaymentRepository) GetByOrderID(ctx context.Context, orderID string) (*model.Payment, error) {
	var p model.Payment
	err := r.pool.QueryRow(ctx,
		`SELECT id, order_id, amount, method, status, created_at
		 FROM payments WHERE order_id=$1 ORDER BY created_at DESC LIMIT 1`, orderID,
	).Scan(&p.ID, &p.OrderID, &p.Amount, &p.Method, &p.Status, &p.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &p, nil
}
