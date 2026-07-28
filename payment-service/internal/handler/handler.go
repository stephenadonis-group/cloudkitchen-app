// Package handler exposes the HTTP API for the payment-service.
package handler

import (
	"errors"
	"net/http"

	"github.com/cloudkitchen/payment-service/internal/middleware"
	"github.com/cloudkitchen/payment-service/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

// Handler holds the service dependencies used by HTTP endpoints.
type Handler struct {
	payments *service.PaymentService
	secret   string
}

// New constructs the HTTP handler.
func New(payments *service.PaymentService, jwtSecret string) *Handler {
	return &Handler{payments: payments, secret: jwtSecret}
}

// Register attaches business routes under /api (operational routes live in main).
func (h *Handler) Register(r *gin.Engine) {
	api := r.Group("/api")
	auth := api.Group("")
	// Any authenticated user may query the payment status of an order.
	auth.Use(middleware.JWTAuth(h.secret))
	{
		auth.GET("/payments/order/:orderId", h.getByOrder)
	}
}

func (h *Handler) getByOrder(c *gin.Context) {
	payment, err := h.payments.GetByOrderID(c.Request.Context(), c.Param("orderId"))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "payment not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, payment)
}
