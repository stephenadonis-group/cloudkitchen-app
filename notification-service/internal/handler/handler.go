// Package handler exposes the HTTP API for the notification-service.
package handler

import (
	"net/http"
	"strconv"

	"github.com/cloudkitchen/notification-service/internal/middleware"
	"github.com/cloudkitchen/notification-service/internal/service"
	"github.com/gin-gonic/gin"
)

// Handler holds the service dependencies used by HTTP endpoints.
type Handler struct {
	notifications *service.NotificationService
	secret        string
}

// New constructs the HTTP handler.
func New(notifications *service.NotificationService, jwtSecret string) *Handler {
	return &Handler{notifications: notifications, secret: jwtSecret}
}

// Register attaches business routes under /api (operational routes live in main).
func (h *Handler) Register(r *gin.Engine) {
	api := r.Group("/api")
	auth := api.Group("")
	auth.Use(middleware.JWTAuth(h.secret))
	{
		auth.GET("/notifications", h.list)
	}
}

// list returns recent notifications. Admins see all; everyone else sees only
// notifications keyed to their own id.
func (h *Handler) list(c *gin.Context) {
	role, _ := c.Get(middleware.CtxRole)
	uid, _ := c.Get(middleware.CtxUserID)

	scope := ""
	if r, _ := role.(string); r != "admin" {
		scope, _ = uid.(string)
	}

	limit := 50
	if q := c.Query("limit"); q != "" {
		if n, err := strconv.Atoi(q); err == nil {
			limit = n
		}
	}

	items, err := h.notifications.ListRecent(c.Request.Context(), scope, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"notifications": items})
}
