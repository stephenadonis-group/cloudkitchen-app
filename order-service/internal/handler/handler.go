// Package handler exposes the HTTP API for the order-service (cart + orders) and
// wires routes onto the Gin engine with the appropriate auth/RBAC middleware.
package handler

import (
	"errors"
	"net/http"

	"github.com/cloudkitchen/order-service/internal/middleware"
	"github.com/cloudkitchen/order-service/internal/model"
	"github.com/cloudkitchen/order-service/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Handler holds the service dependencies used by HTTP endpoints.
type Handler struct {
	orders *service.OrderService
	carts  *service.CartService
	secret string
}

// New constructs the HTTP handler.
func New(orders *service.OrderService, carts *service.CartService, jwtSecret string) *Handler {
	return &Handler{orders: orders, carts: carts, secret: jwtSecret}
}

// Register attaches all business routes under /api. Operational routes
// (/healthz, /readyz, /metrics) remain registered in main.
func (h *Handler) Register(r *gin.Engine) {
	api := r.Group("/api")

	// All cart + order routes require an authenticated customer.
	auth := api.Group("")
	auth.Use(middleware.JWTAuth(h.secret), middleware.RequireRole("customer"))
	{
		auth.POST("/cart/items", h.addCartItem)
		auth.GET("/cart", h.getCart)
		auth.DELETE("/cart/items/:itemId", h.removeCartItem)
		auth.DELETE("/cart", h.clearCart)

		auth.POST("/orders", h.createOrder)
		auth.GET("/orders", h.listOrders)
		auth.GET("/orders/:id", h.getOrder)
		auth.GET("/orders/:id/track", h.trackOrder)
	}
}

// customerID extracts the authenticated user's id from the context.
func customerID(c *gin.Context) string {
	v, _ := c.Get(middleware.CtxUserID)
	id, _ := v.(string)
	return id
}

func (h *Handler) addCartItem(c *gin.Context) {
	var item model.CartItem
	if err := c.ShouldBindJSON(&item); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	cart, err := h.carts.AddOrUpdate(c.Request.Context(), customerID(c), item)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, cart)
}

func (h *Handler) getCart(c *gin.Context) {
	cart, err := h.carts.Get(c.Request.Context(), customerID(c))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, cart)
}

func (h *Handler) removeCartItem(c *gin.Context) {
	cart, err := h.carts.RemoveItem(c.Request.Context(), customerID(c), c.Param("itemId"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, cart)
}

func (h *Handler) clearCart(c *gin.Context) {
	if err := h.carts.Clear(c.Request.Context(), customerID(c)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "cleared"})
}

func (h *Handler) createOrder(c *gin.Context) {
	var req model.CreateOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	order, err := h.orders.PlaceOrder(c.Request.Context(), customerID(c), req.RestaurantID)
	if err != nil {
		if errors.Is(err, service.ErrEmptyCart) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "cart is empty"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, order)
}

func (h *Handler) listOrders(c *gin.Context) {
	orders, err := h.orders.ListOrders(c.Request.Context(), customerID(c))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"orders": orders})
}

// fetchOwnedOrder loads an order and enforces that it belongs to the caller.
func (h *Handler) fetchOwnedOrder(c *gin.Context) (*model.Order, bool) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid order id"})
		return nil, false
	}
	order, err := h.orders.GetOrder(c.Request.Context(), id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "order not found"})
			return nil, false
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return nil, false
	}
	if order.CustomerID != customerID(c) {
		c.JSON(http.StatusForbidden, gin.H{"error": "not your order"})
		return nil, false
	}
	return order, true
}

func (h *Handler) getOrder(c *gin.Context) {
	if order, ok := h.fetchOwnedOrder(c); ok {
		c.JSON(http.StatusOK, order)
	}
}

func (h *Handler) trackOrder(c *gin.Context) {
	if order, ok := h.fetchOwnedOrder(c); ok {
		c.JSON(http.StatusOK, gin.H{"order_id": order.ID, "status": order.Status})
	}
}
