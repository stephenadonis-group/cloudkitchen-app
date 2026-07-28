package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/cloudkitchen/delivery-service/internal/model"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DeliveryRepository persists agents and deliveries.
type DeliveryRepository struct {
	pool *pgxpool.Pool
}

// NewDeliveryRepository wires the repository to a pgx pool.
func NewDeliveryRepository(pool *pgxpool.Pool) *DeliveryRepository {
	return &DeliveryRepository{pool: pool}
}

// AssignAndCreate atomically picks an available agent, marks them unavailable and
// creates an ASSIGNED delivery for the order. Returns pgx.ErrNoRows if no agent
// is available.
func (r *DeliveryRepository) AssignAndCreate(ctx context.Context, orderID string) (*model.Delivery, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op after commit

	// Lock one available agent to avoid double-assignment under concurrency.
	var agentID uuid.UUID
	err = tx.QueryRow(ctx,
		`SELECT id FROM agents WHERE available = TRUE
		 ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED`,
	).Scan(&agentID)
	if err != nil {
		return nil, err // pgx.ErrNoRows when none available
	}

	if _, err := tx.Exec(ctx, `UPDATE agents SET available = FALSE WHERE id=$1`, agentID); err != nil {
		return nil, fmt.Errorf("mark agent busy: %w", err)
	}

	now := time.Now().UTC()
	d := &model.Delivery{
		ID:        uuid.New(),
		OrderID:   orderID,
		AgentID:   &agentID,
		Status:    model.StatusAssigned,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO deliveries (id, order_id, agent_id, status, created_at, updated_at)
		 VALUES ($1,$2,$3,$4,$5,$6)`,
		d.ID, d.OrderID, d.AgentID, d.Status, d.CreatedAt, d.UpdatedAt,
	); err != nil {
		return nil, fmt.Errorf("insert delivery: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit tx: %w", err)
	}
	return d, nil
}

// GetByID returns a delivery by its UUID, or pgx.ErrNoRows.
func (r *DeliveryRepository) GetByID(ctx context.Context, id uuid.UUID) (*model.Delivery, error) {
	var d model.Delivery
	err := r.pool.QueryRow(ctx,
		`SELECT id, order_id, agent_id, status, created_at, updated_at
		 FROM deliveries WHERE id=$1`, id,
	).Scan(&d.ID, &d.OrderID, &d.AgentID, &d.Status, &d.CreatedAt, &d.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// GetByOrderID returns the delivery for an order, or pgx.ErrNoRows.
func (r *DeliveryRepository) GetByOrderID(ctx context.Context, orderID string) (*model.Delivery, error) {
	var d model.Delivery
	err := r.pool.QueryRow(ctx,
		`SELECT id, order_id, agent_id, status, created_at, updated_at
		 FROM deliveries WHERE order_id=$1 ORDER BY created_at DESC LIMIT 1`, orderID,
	).Scan(&d.ID, &d.OrderID, &d.AgentID, &d.Status, &d.CreatedAt, &d.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// UpdateStatus sets a new status (and, when DELIVERED, frees the agent) and
// returns the updated delivery. Returns pgx.ErrNoRows if the delivery is absent.
func (r *DeliveryRepository) UpdateStatus(ctx context.Context, id uuid.UUID, status string) (*model.Delivery, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op after commit

	var d model.Delivery
	err = tx.QueryRow(ctx,
		`UPDATE deliveries SET status=$1, updated_at=now() WHERE id=$2
		 RETURNING id, order_id, agent_id, status, created_at, updated_at`,
		status, id,
	).Scan(&d.ID, &d.OrderID, &d.AgentID, &d.Status, &d.CreatedAt, &d.UpdatedAt)
	if err != nil {
		return nil, err // pgx.ErrNoRows if not found
	}

	// Free the agent once the delivery completes so they can take new jobs.
	if status == model.StatusDelivered && d.AgentID != nil {
		if _, err := tx.Exec(ctx, `UPDATE agents SET available = TRUE WHERE id=$1`, *d.AgentID); err != nil {
			return nil, fmt.Errorf("free agent: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit tx: %w", err)
	}
	return &d, nil
}
