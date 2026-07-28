// Package handler exposes the HTTP layer for menu-service and registers routes.
package handler

import (
	"net/http"

	"github.com/cloudkitchen/menu-service/internal/middleware"
	"github.com/cloudkitchen/menu-service/internal/model"
	"github.com/cloudkitchen/menu-service/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// MenuHandler wires HTTP requests to the MenuService.
type MenuHandler struct {
	svc *service.MenuService
}

// NewMenuHandler constructs a MenuHandler.
func NewMenuHandler(svc *service.MenuService) *MenuHandler {
	return &MenuHandler{svc: svc}
}

// Register mounts public reads and restaurant-admin protected writes.
func (h *MenuHandler) Register(r *gin.Engine, jwtSecret string) {
	rg := r.Group("/api/restaurants/:rid")
	// Public read of a restaurant's full menu.
	rg.GET("/menu", h.getMenu)
	// Protected writes (restaurant-admin only).
	auth := rg.Group("", middleware.JWTAuth(jwtSecret), middleware.RequireRole("restaurant-admin"))
	auth.POST("/categories", h.createCategory)
	auth.POST("/items", h.createItem)

	// Public cross-restaurant search.
	r.GET("/api/menu/search", h.search)
}

// ridParam parses the :rid path parameter.
func ridParam(c *gin.Context) (uuid.UUID, bool) {
	rid, err := uuid.Parse(c.Param("rid"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid restaurant id"})
		return uuid.Nil, false
	}
	return rid, true
}

func (h *MenuHandler) createCategory(c *gin.Context) {
	rid, ok := ridParam(c)
	if !ok {
		return
	}
	var req model.CreateCategoryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	cat, err := h.svc.CreateCategory(c.Request.Context(), rid, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create category"})
		return
	}
	c.JSON(http.StatusCreated, cat)
}

func (h *MenuHandler) createItem(c *gin.Context) {
	rid, ok := ridParam(c)
	if !ok {
		return
	}
	var req model.CreateItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	item, err := h.svc.CreateItem(c.Request.Context(), rid, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create item"})
		return
	}
	c.JSON(http.StatusCreated, item)
}

func (h *MenuHandler) getMenu(c *gin.Context) {
	rid, ok := ridParam(c)
	if !ok {
		return
	}
	m, err := h.svc.GetMenu(c.Request.Context(), rid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load menu"})
		return
	}
	c.JSON(http.StatusOK, m)
}

func (h *MenuHandler) search(c *gin.Context) {
	q := c.Query("q")
	if q == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing query parameter q"})
		return
	}
	items, err := h.svc.Search(c.Request.Context(), q)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
		return
	}
	c.JSON(http.StatusOK, items)
}
