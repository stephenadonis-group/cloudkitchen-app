// Package main is the entrypoint for auth-service.
//
// It keeps the operational endpoints (/healthz, /readyz, /metrics) from the
// skeleton and wires in the business layer: config, Postgres (schema-per-service
// with embedded migrations), NATS broker, and the auth HTTP API.
//
// GitOps loop verification marker — see Phase 4d in docs/gcp/04-argocd-deploy.md.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/cloudkitchen/auth-service/internal/config"
	"github.com/cloudkitchen/auth-service/internal/handler"
	"github.com/cloudkitchen/auth-service/internal/middleware"
	"github.com/cloudkitchen/auth-service/internal/repository"
	"github.com/cloudkitchen/auth-service/internal/service"
	"github.com/cloudkitchen/auth-service/migrations"
	"github.com/cloudkitchen/auth-service/pkg/broker"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// parseLevel maps a LOG_LEVEL string to an slog.Level.
func parseLevel(s string) slog.Level {
	switch s {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

func main() {
	cfg := config.Load()

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: parseLevel(cfg.LogLevel)}))
	slog.SetDefault(logger)

	ctx := context.Background()

	// --- Database: connect, ensure schema, run migrations. ---
	pool, err := repository.Connect(ctx, cfg.DSN(), cfg.DBSchema)
	if err != nil {
		logger.Error("db connect failed", "error", err)
		os.Exit(1)
	}
	defer pool.Close()
	if err := repository.RunMigrations(ctx, pool, cfg.DBSchema, migrations.FS, "."); err != nil {
		logger.Error("migrations failed", "error", err)
		os.Exit(1)
	}

	// --- Messaging: NATS broker (REQUIRED — auth publishes user.registered events).
	// Fail fast so Kubernetes restarts us until NATS is healthy. A "soft-fail"
	// would leave the service running with publishes silently disabled, which
	// breaks downstream consumers (e.g. user-service's profile auto-create).
	b, err := broker.New(cfg.NATSURL, logger)
	if err != nil {
		logger.Error("nats connect failed", "error", err)
		os.Exit(1)
	}
	defer b.Close()

	// --- Wire layers: repository -> service -> handler. ---
	userRepo := repository.NewUserRepository(pool)
	authSvc := service.NewAuthService(userRepo, b, cfg.JWTSecret, cfg.JWTExpiry)
	authHandler := handler.NewAuthHandler(authSvc)

	gin.SetMode(gin.ReleaseMode)
	router := gin.New()
	router.Use(gin.Recovery(), middleware.RequestLogger(logger), middleware.Metrics(cfg.ServiceName))

	router.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": cfg.ServiceName})
	})
	router.GET("/readyz", func(c *gin.Context) {
		if err := pool.Ping(c.Request.Context()); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "not ready", "error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ready", "service": cfg.ServiceName})
	})
	router.GET("/metrics", gin.WrapH(promhttp.Handler()))

	authHandler.Register(router, cfg.JWTSecret)

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		logger.Info("server starting", "service", cfg.ServiceName, "port", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server failed", "error", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	logger.Info("server shutting down", "service", cfg.ServiceName)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("forced shutdown", "error", err)
	}
	logger.Info("server stopped", "service", cfg.ServiceName)
}
