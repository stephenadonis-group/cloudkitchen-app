import client from './client'

// Menu service — matches the live backend:
//   GET  /api/restaurants/:rid/menu      -> { restaurant_id, categories[], items[] }
//   POST /api/restaurants/:rid/categories { name }
//   POST /api/restaurants/:rid/items      { category_id, name, description, price, available }
//   GET  /api/menu/search?q=
export const menuApi = {
  forRestaurant: (rid) =>
    client.get(`/api/restaurants/${rid}/menu`).then((r) => r.data),
  addCategory: (rid, payload) =>
    client.post(`/api/restaurants/${rid}/categories`, payload).then((r) => r.data),
  addItem: (rid, payload) =>
    client.post(`/api/restaurants/${rid}/items`, payload).then((r) => r.data),
  search: (q) => client.get('/api/menu/search', { params: { q } }).then((r) => r.data),
}
