package repository

import (
	"context"
	"fmt"

	"github.com/cloudkitchen/order-service/internal/model"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// OrderRepository persists orders and their line items.
type OrderRepository struct {
	pool *pgxpool.Pool
}

// NewOrderRepository wires the repository to a pgx pool.
func NewOrderRepository(pool *pgxpool.Pool) *OrderRepository {
	return &OrderRepository{pool: pool}
}

// Create inserts an order header and all its items inside a single transaction.
func (r *OrderRepository) Create(ctx context.Context, o *model.Order) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op after commit

	if _, err := tx.Exec(ctx,
		`INSERT INTO orders (id, customer_id, restaurant_id, status, total, created_at)
		 VALUES ($1,$2,$3,$4,$5,$6)`,
		o.ID, o.CustomerID, o.RestaurantID, o.Status, o.Total, o.CreatedAt,
	); err != nil {
		return fmt.Errorf("insert order: %w", err)
	}

	for i := range o.Items {
		it := &o.Items[i]
		it.ID = uuid.New()
		it.OrderID = o.ID
		if _, err := tx.Exec(ctx,
			`INSERT INTO order_items (id, order_id, item_id, name, qty, price)
			 VALUES ($1,$2,$3,$4,$5,$6)`,
			it.ID, it.OrderID, it.ItemID, it.Name, it.Qty, it.Price,
		); err != nil {
			return fmt.Errorf("insert order item: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit tx: %w", err)
	}
	return nil
}

// GetByID returns an order with its items, or pgx.ErrNoRows if not found.
func (r *OrderRepository) GetByID(ctx context.Context, id uuid.UUID) (*model.Order, error) {
	var o model.Order
	err := r.pool.QueryRow(ctx,
		`SELECT id, customer_id, restaurant_id, status, total, created_at
		 FROM orders WHERE id=$1`, id,
	).Scan(&o.ID, &o.CustomerID, &o.RestaurantID, &o.Status, &o.Total, &o.CreatedAt)
	if err != nil {
		return nil, err
	}

	rows, err := r.pool.Query(ctx,
		`SELECT id, order_id, item_id, name, qty, price
		 FROM order_items WHERE order_id=$1`, id)
	if err != nil {
		return nil, fmt.Errorf("query items: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var it model.OrderItem
		if err := rows.Scan(&it.ID, &it.OrderID, &it.ItemID, &it.Name, &it.Qty, &it.Price); err != nil {
			return nil, fmt.Errorf("scan item: %w", err)
		}
		o.Items = append(o.Items, it)
	}
	return &o, rows.Err()
}

// ListByCustomer returns a customer's order history, newest first.
func (r *OrderRepository) ListByCustomer(ctx context.Context, customerID string) ([]model.Order, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, customer_id, restaurant_id, status, total, created_at
		 FROM orders WHERE customer_id=$1 ORDER BY created_at DESC`, customerID)
	if err != nil {
		return nil, fmt.Errorf("query orders: %w", err)
	}
	defer rows.Close()
	var out []model.Order
	for rows.Next() {
		var o model.Order
		if err := rows.Scan(&o.ID, &o.CustomerID, &o.RestaurantID, &o.Status, &o.Total, &o.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan order: %w", err)
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

// UpdateStatusByOrderID sets the status for the order identified by its UUID
// string. Used by event consumers. Returns pgx.ErrNoRows if no row matched.
func (r *OrderRepository) UpdateStatusByOrderID(ctx context.Context, orderID, status string) error {
	id, err := uuid.Parse(orderID)
	if err != nil {
		return fmt.Errorf("parse order id: %w", err)
	}
	tag, err := r.pool.Exec(ctx, `UPDATE orders SET status=$1 WHERE id=$2`, status, id)
	if err != nil {
		return fmt.Errorf("update status: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}
