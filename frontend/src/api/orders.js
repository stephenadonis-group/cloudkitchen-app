import client from './client'

// Cart + Orders + Payments + Deliveries + Notifications services.

// Cart (order-service): server-side cart keyed by the auth token.
//   POST /api/cart/items { item_id, name, qty, price }
//   GET  /api/cart
//   DELETE /api/cart/items/:itemId
//   DELETE /api/cart
export const cartApi = {
  get: () => client.get('/api/cart').then((r) => r.data),
  addItem: (payload) => client.post('/api/cart/items', payload).then((r) => r.data),
  removeItem: (itemId) =>
    client.delete(`/api/cart/items/${itemId}`).then((r) => r.data),
  clear: () => client.delete('/api/cart').then((r) => r.data),
}

// Orders: POST /api/orders { restaurant_id } -> the server builds the order from
// the current server-side cart and returns { id, status, total, items[] }.
export const ordersApi = {
  list: () => client.get('/api/orders').then((r) => r.data),
  get: (id) => client.get(`/api/orders/${id}`).then((r) => r.data),
  create: (payload) => client.post('/api/orders', payload).then((r) => r.data),
  track: (id) => client.get(`/api/orders/${id}/track`).then((r) => r.data),
}

// Payments are created server-side as part of order placement; the UI reads them.
export const paymentsApi = {
  forOrder: (orderId) =>
    client.get(`/api/payments/order/${orderId}`).then((r) => r.data),
}

export const deliveriesApi = {
  forOrder: (orderId) =>
    client.get(`/api/deliveries/order/${orderId}`).then((r) => r.data),
}

// GET /api/notifications -> { notifications: [{ id, user_id, channel, type, payload, sent_at }] }
export const notificationsApi = {
  list: () => client.get('/api/notifications').then((r) => r.data),
}
