import axios from 'axios'

// Single axios instance for the whole app.
// baseURL comes from VITE_API_BASE_URL (default "/" so it works behind the
// shared ingress in production). All domain modules import this client.
const baseURL = import.meta.env.VITE_API_BASE_URL || '/'

const client = axios.create({
  baseURL,
  headers: { 'Content-Type': 'application/json' },
})

export const TOKEN_KEY = 'ck_token'

// Request interceptor: attach the JWT (if present) as a Bearer token.
client.interceptors.request.use((config) => {
  const token = localStorage.getItem(TOKEN_KEY)
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

// Response interceptor: on 401 clear the token and bounce to /login.
client.interceptors.response.use(
  (res) => res,
  (error) => {
    if (error.response && error.response.status === 401) {
      localStorage.removeItem(TOKEN_KEY)
      // Avoid redirect loops if we're already on the login page.
      if (!window.location.pathname.startsWith('/login')) {
        window.location.assign('/login')
      }
    }
    return Promise.reject(error)
  }
)

export default client
