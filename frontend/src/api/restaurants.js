import client from './client'

// Restaurants service — /api/restaurants/*
export const restaurantsApi = {
  list: (params) => client.get('/api/restaurants', { params }).then((r) => r.data),
  get: (rid) => client.get(`/api/restaurants/${rid}`).then((r) => r.data),
  create: (payload) => client.post('/api/restaurants', payload).then((r) => r.data),
}
