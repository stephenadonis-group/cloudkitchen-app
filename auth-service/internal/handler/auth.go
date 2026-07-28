// Package handler exposes the HTTP layer for auth-service and registers routes.
package handler

import (
	"errors"
	"net/http"

	"github.com/cloudkitchen/auth-service/internal/middleware"
	"github.com/cloudkitchen/auth-service/internal/model"
	"github.com/cloudkitchen/auth-service/internal/service"
	"github.com/gin-gonic/gin"
)

// AuthHandler wires HTTP requests to the AuthService.
type AuthHandler struct {
	svc *service.AuthService
}

// NewAuthHandler constructs an AuthHandler.
func NewAuthHandler(svc *service.AuthService) *AuthHandler {
	return &AuthHandler{svc: svc}
}

// Register mounts the auth routes onto the router group. jwtSecret is used to
// protect the /me endpoint.
func (h *AuthHandler) Register(r *gin.Engine, jwtSecret string) {
	g := r.Group("/api/auth")
	g.POST("/register", h.register)
	g.POST("/login", h.login)
	g.GET("/me", middleware.JWTAuth(jwtSecret), h.me)
}

func (h *AuthHandler) register(c *gin.Context) {
	var req model.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	u, err := h.svc.Register(c.Request.Context(), req)
	if errors.Is(err, service.ErrEmailTaken) {
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "registration failed"})
		return
	}
	c.JSON(http.StatusCreated, u)
}

func (h *AuthHandler) login(c *gin.Context) {
	var req model.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	token, err := h.svc.Login(c.Request.Context(), req)
	if errors.Is(err, service.ErrInvalidCredentials) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "login failed"})
		return
	}
	c.JSON(http.StatusOK, model.LoginResponse{Token: token})
}

// me returns the authenticated caller's claims.
func (h *AuthHandler) me(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"user_id": c.GetString(middleware.CtxUserID),
		"email":   c.GetString(middleware.CtxEmail),
		"role":    c.GetString(middleware.CtxRole),
	})
}
