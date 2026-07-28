// Package handler exposes the HTTP layer for user-service and registers routes.
package handler

import (
	"errors"
	"net/http"

	"github.com/cloudkitchen/user-service/internal/middleware"
	"github.com/cloudkitchen/user-service/internal/model"
	"github.com/cloudkitchen/user-service/internal/repository"
	"github.com/cloudkitchen/user-service/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// UserHandler wires HTTP requests to the UserService.
type UserHandler struct {
	svc *service.UserService
}

// NewUserHandler constructs a UserHandler.
func NewUserHandler(svc *service.UserService) *UserHandler {
	return &UserHandler{svc: svc}
}

// Register mounts the user routes (all JWT-protected) onto the engine.
func (h *UserHandler) Register(r *gin.Engine, jwtSecret string) {
	g := r.Group("/api/users/me", middleware.JWTAuth(jwtSecret))
	g.GET("/profile", h.getProfile)
	g.PUT("/profile", h.updateProfile)
	g.GET("/addresses", h.listAddresses)
	g.POST("/addresses", h.createAddress)
	g.DELETE("/addresses/:id", h.deleteAddress)
}

// callerID extracts and parses the authenticated user id from context.
func callerID(c *gin.Context) (uuid.UUID, bool) {
	id, err := uuid.Parse(c.GetString(middleware.CtxUserID))
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid subject in token"})
		return uuid.Nil, false
	}
	return id, true
}

func (h *UserHandler) getProfile(c *gin.Context) {
	uid, ok := callerID(c)
	if !ok {
		return
	}
	p, err := h.svc.GetProfile(c.Request.Context(), uid)
	if errors.Is(err, repository.ErrNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": "profile not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load profile"})
		return
	}
	c.JSON(http.StatusOK, p)
}

func (h *UserHandler) updateProfile(c *gin.Context) {
	uid, ok := callerID(c)
	if !ok {
		return
	}
	var req model.UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	p, err := h.svc.UpdateProfile(c.Request.Context(), uid, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update profile"})
		return
	}
	c.JSON(http.StatusOK, p)
}

func (h *UserHandler) listAddresses(c *gin.Context) {
	uid, ok := callerID(c)
	if !ok {
		return
	}
	addrs, err := h.svc.ListAddresses(c.Request.Context(), uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list addresses"})
		return
	}
	c.JSON(http.StatusOK, addrs)
}

func (h *UserHandler) createAddress(c *gin.Context) {
	uid, ok := callerID(c)
	if !ok {
		return
	}
	var req model.CreateAddressRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	a, err := h.svc.CreateAddress(c.Request.Context(), uid, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create address"})
		return
	}
	c.JSON(http.StatusCreated, a)
}

func (h *UserHandler) deleteAddress(c *gin.Context) {
	uid, ok := callerID(c)
	if !ok {
		return
	}
	addrID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid address id"})
		return
	}
	err = h.svc.DeleteAddress(c.Request.Context(), uid, addrID)
	if errors.Is(err, repository.ErrNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": "address not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete address"})
		return
	}
	c.Status(http.StatusNoContent)
}
