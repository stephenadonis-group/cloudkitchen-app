// Package broker is a thin wrapper around NATS JetStream implementing the
// CloudKitchen event-bus convention: a single JetStream stream "CLOUDKITCHEN"
// covers all subjects under "cloudkitchen.>" (e.g. "cloudkitchen.order.placed").
//
// Public API is intentionally unchanged from the previous AMQP implementation
// so call sites in service / main.go don't need to change:
//   - Publish(eventName, payload)  e.g. Publish("order.placed", evt)
//   - Consume(consumerName, []string{events...}, handler)
//
// The broker internally maps:
//   eventName "order.placed"  ->  NATS subject "cloudkitchen.order.placed"
//   consumerName "payment-service.events" -> JetStream durable "payment-service-events"
// (JetStream durable names cannot contain dots; they are sanitized to dashes.)
//
// Delivery semantics: JetStream + AckExplicit + MaxDeliver=2 gives at-least-once
// with a single retry on handler error, then drop (poison-message safe). This
// matches the old RabbitMQ "nack + requeue once" behavior.
package broker

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
)

// StreamName is the shared JetStream stream every CloudKitchen service publishes into.
const StreamName = "CLOUDKITCHEN"

// SubjectPrefix is prepended to every event name to form the NATS subject.
// e.g. event "order.placed" -> subject "cloudkitchen.order.placed".
const SubjectPrefix = "cloudkitchen"

// Handler processes a single decoded event payload.
// `eventName` is the bare event name (e.g. "order.placed"), with the
// SubjectPrefix already stripped, so handlers can switch on it directly.
// Returning an error causes the message to be nak'd; JetStream will redeliver
// per the consumer's MaxDeliver policy.
type Handler func(eventName string, body []byte) error

// Broker owns the NATS connection, JetStream context, and the shared stream.
type Broker struct {
	nc        *nats.Conn
	js        jetstream.JetStream
	stream    jetstream.Stream
	logger    *slog.Logger
	consumers []jetstream.ConsumeContext // keep ConsumeContexts alive
}

// New dials NATS, opens JetStream, and ensures the shared stream exists.
// `url` is e.g. "nats://nats:4222" (no credentials needed in dev).
func New(url string, logger *slog.Logger) (*Broker, error) {
	if logger == nil {
		logger = slog.Default()
	}

	nc, err := nats.Connect(url,
		nats.RetryOnFailedConnect(true),
		nats.MaxReconnects(-1),
		nats.ReconnectWait(2*time.Second),
		nats.Timeout(5*time.Second),
		nats.Name("cloudkitchen"),
	)
	if err != nil {
		return nil, fmt.Errorf("nats connect: %w", err)
	}

	js, err := jetstream.New(nc)
	if err != nil {
		nc.Close()
		return nil, fmt.Errorf("jetstream context: %w", err)
	}

	// Ensure the shared stream exists (idempotent — every service may call this).
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	stream, err := js.CreateOrUpdateStream(ctx, jetstream.StreamConfig{
		Name:        StreamName,
		Description: "CloudKitchen event bus (user/restaurant/order/payment/delivery/notification events)",
		Subjects:    []string{SubjectPrefix + ".>"},
		Storage:     jetstream.FileStorage,
		Retention:   jetstream.LimitsPolicy,
		MaxAge:      24 * time.Hour,
		MaxBytes:    -1,
		Discard:     jetstream.DiscardOld,
	})
	if err != nil {
		nc.Close()
		return nil, fmt.Errorf("ensure stream %q: %w", StreamName, err)
	}

	logger.Info("nats connected", "url", url, "stream", StreamName)
	return &Broker{nc: nc, js: js, stream: stream, logger: logger}, nil
}

// Publish marshals payload to JSON and publishes it to the NATS subject
// "cloudkitchen.<eventName>". Blocks until JetStream acknowledges storage.
func (b *Broker) Publish(eventName string, payload any) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}

	subject := SubjectPrefix + "." + eventName
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if _, err := b.js.Publish(ctx, subject, body); err != nil {
		return fmt.Errorf("publish %q: %w", subject, err)
	}
	b.logger.Info("event published", "subject", subject)
	return nil
}

// Consume registers a durable JetStream consumer that receives the listed events.
// Messages are dispatched to handler synchronously; ack/nak is handled internally.
//
// `consumerName` is used as the JetStream durable (dots in the name are sanitized
// to dashes since JetStream durables cannot contain dots).
// `eventNames` is e.g. []string{"order.placed", "payment.completed"} — the
// broker maps each to its full subject "cloudkitchen.<event>".
func (b *Broker) Consume(consumerName string, eventNames []string, handler Handler) error {
	if handler == nil {
		return errors.New("handler is required")
	}
	if len(eventNames) == 0 {
		return errors.New("at least one event name is required")
	}

	durable := sanitizeDurable(consumerName)
	filters := make([]string, 0, len(eventNames))
	for _, ev := range eventNames {
		filters = append(filters, SubjectPrefix+"."+ev)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cons, err := b.stream.CreateOrUpdateConsumer(ctx, jetstream.ConsumerConfig{
		Durable:        durable,
		FilterSubjects: filters,
		AckPolicy:      jetstream.AckExplicitPolicy,
		MaxDeliver:     2, // retry once on handler error, then drop (poison-message safe)
		AckWait:        30 * time.Second,
		DeliverPolicy:  jetstream.DeliverAllPolicy,
	})
	if err != nil {
		return fmt.Errorf("create consumer %q: %w", durable, err)
	}

	cc, err := cons.Consume(func(msg jetstream.Msg) {
		// Strip the prefix so handler sees the bare event name (matches old API).
		eventName := strings.TrimPrefix(msg.Subject(), SubjectPrefix+".")
		if err := handler(eventName, msg.Data()); err != nil {
			b.logger.Error("event handler failed", "subject", msg.Subject(), "error", err)
			_ = msg.Nak()
			return
		}
		_ = msg.Ack()
	})
	if err != nil {
		return fmt.Errorf("consume %q: %w", durable, err)
	}
	b.consumers = append(b.consumers, cc)
	b.logger.Info("consumer started", "durable", durable, "filters", filters)
	return nil
}

// Close stops all active consumers and drains the NATS connection.
func (b *Broker) Close() {
	for _, cc := range b.consumers {
		cc.Stop()
	}
	if b.nc != nil {
		_ = b.nc.Drain()
	}
}

// sanitizeDurable converts dotted names (legacy from RabbitMQ queue conventions)
// to a JetStream-valid durable name: "payment-service.events" -> "payment-service-events".
func sanitizeDurable(s string) string {
	return strings.ReplaceAll(s, ".", "-")
}
