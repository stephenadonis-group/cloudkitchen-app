import client from './client'

// Auth service — /api/auth/*
export const authApi = {
  register: (payload) => client.post('/api/auth/register', payload).then((r) => r.data),
  login: (payload) => client.post('/api/auth/login', payload).then((r) => r.data),
  me: () => client.get('/api/auth/me').then((r) => r.data),
}
