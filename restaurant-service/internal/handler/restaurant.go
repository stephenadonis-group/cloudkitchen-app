// Package handler exposes the HTTP layer for restaurant-service and registers routes.
package handler

import (
	"errors"
	"net/http"

	"github.com/cloudkitchen/restaurant-service/internal/middleware"
	"github.com/cloudkitchen/restaurant-service/internal/model"
	"github.com/cloudkitchen/restaurant-service/internal/repository"
	"github.com/cloudkitchen/restaurant-service/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// RestaurantHandler wires HTTP requests to the RestaurantService.
type RestaurantHandler struct {
	svc *service.RestaurantService
}

// NewRestaurantHandler constructs a RestaurantHandler.
func NewRestaurantHandler(svc *service.RestaurantService) *RestaurantHandler {
	return &RestaurantHandler{svc: svc}
}

// Register mounts public and protected restaurant routes.
func (h *RestaurantHandler) Register(r *gin.Engine, jwtSecret string) {
	g := r.Group("/api/restaurants")
	// Public reads.
	g.GET("", h.list)
	g.GET("/:id", h.get)
	// Protected writes.
	auth := g.Group("", middleware.JWTAuth(jwtSecret))
	auth.POST("", middleware.RequireRole("restaurant-admin"), h.create)
	auth.PUT("/:id", h.update)
}

func (h *RestaurantHandler) create(c *gin.Context) {
	ownerID, err := uuid.Parse(c.GetString(middleware.CtxUserID))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid subject in token"})
		return
	}
	var req model.CreateRestaurantRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	m, err := h.svc.Create(c.Request.Context(), ownerID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create restaurant"})
		return
	}
	c.JSON(http.StatusCreated, m)
}

func (h *RestaurantHandler) list(c *gin.Context) {
	city := c.Query("city")
	items, err := h.svc.List(c.Request.Context(), city)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list restaurants"})
		return
	}
	c.JSON(http.StatusOK, items)
}

func (h *RestaurantHandler) get(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid restaurant id"})
		return
	}
	m, err := h.svc.Get(c.Request.Context(), id)
	if errors.Is(err, repository.ErrNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": "restaurant not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load restaurant"})
		return
	}
	c.JSON(http.StatusOK, m)
}

func (h *RestaurantHandler) update(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid restaurant id"})
		return
	}
	callerID, err := uuid.Parse(c.GetString(middleware.CtxUserID))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid subject in token"})
		return
	}
	var req model.UpdateRestaurantRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	m, err := h.svc.Update(c.Request.Context(), id, callerID, c.GetString(middleware.CtxRole), req)
	if errors.Is(err, repository.ErrNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": "restaurant not found"})
		return
	}
	if errors.Is(err, service.ErrForbidden) {
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update restaurant"})
		return
	}
	c.JSON(http.StatusOK, m)
}
