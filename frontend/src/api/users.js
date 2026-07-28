import client from './client'

// Users service — /api/users/me/*
export const usersApi = {
  getProfile: () => client.get('/api/users/me/profile').then((r) => r.data),
  updateProfile: (payload) =>
    client.put('/api/users/me/profile', payload).then((r) => r.data),
  getAddresses: () => client.get('/api/users/me/addresses').then((r) => r.data),
  addAddress: (payload) =>
    client.post('/api/users/me/addresses', payload).then((r) => r.data),
}
