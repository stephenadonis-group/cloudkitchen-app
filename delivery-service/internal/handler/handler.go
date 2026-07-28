// Package handler exposes the HTTP API for the delivery-service.
package handler

import (
	"errors"
	"net/http"

	"github.com/cloudkitchen/delivery-service/internal/middleware"
	"github.com/cloudkitchen/delivery-service/internal/model"
	"github.com/cloudkitchen/delivery-service/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Handler holds the service dependencies used by HTTP endpoints.
type Handler struct {
	deliveries *service.DeliveryService
	secret     string
}

// New constructs the HTTP handler.
func New(deliveries *service.DeliveryService, jwtSecret string) *Handler {
	return &Handler{deliveries: deliveries, secret: jwtSecret}
}

// Register attaches business routes under /api (operational routes live in main).
func (h *Handler) Register(r *gin.Engine) {
	api := r.Group("/api")

	// Agents update delivery status; restricted to the delivery-agent role.
	agent := api.Group("")
	agent.Use(middleware.JWTAuth(h.secret), middleware.RequireRole("delivery-agent"))
	{
		agent.PUT("/deliveries/:id/status", h.updateStatus)
	}

	// Any authenticated user may read a delivery by order id.
	auth := api.Group("")
	auth.Use(middleware.JWTAuth(h.secret))
	{
		auth.GET("/deliveries/order/:orderId", h.getByOrder)
	}
}

func (h *Handler) updateStatus(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid delivery id"})
		return
	}
	var req model.UpdateStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	d, err := h.deliveries.UpdateStatus(c.Request.Context(), id, req.Status)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrInvalidStatus):
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status (use PICKED_UP, OUT_FOR_DELIVERY or DELIVERED)"})
		case errors.Is(err, pgx.ErrNoRows):
			c.JSON(http.StatusNotFound, gin.H{"error": "delivery not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}
	c.JSON(http.StatusOK, d)
}

func (h *Handler) getByOrder(c *gin.Context) {
	d, err := h.deliveries.GetByOrderID(c.Request.Context(), c.Param("orderId"))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "delivery not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, d)
}
