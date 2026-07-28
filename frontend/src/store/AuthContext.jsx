import { createContext, useContext, useEffect, useState, useCallback } from 'react'
import { authApi } from '../api/auth'
import { TOKEN_KEY } from '../api/client'

// Auth context: owns the JWT + current user. Token persists in localStorage so
// sessions survive reloads; the axios interceptor reads the same key.
const AuthContext = createContext(null)

const USER_KEY = 'ck_user'

function decodeToken(token) {
  // Best-effort JWT payload decode (no verification — server enforces that).
  try {
    const payload = token.split('.')[1]
    return JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')))
  } catch {
    return null
  }
}

export function AuthProvider({ children }) {
  const [token, setToken] = useState(() => localStorage.getItem(TOKEN_KEY))
  const [user, setUser] = useState(() => {
    const raw = localStorage.getItem(USER_KEY)
    return raw ? JSON.parse(raw) : null
  })
  const [loading, setLoading] = useState(Boolean(localStorage.getItem(TOKEN_KEY)))

  // Persist user to localStorage whenever it changes.
  useEffect(() => {
    if (user) localStorage.setItem(USER_KEY, JSON.stringify(user))
    else localStorage.removeItem(USER_KEY)
  }, [user])

  // On mount (or when token changes) hydrate the user from /api/auth/me.
  useEffect(() => {
    let active = true
    if (!token) {
      setLoading(false)
      return
    }
    setLoading(true)
    authApi
      .me()
      .then((me) => {
        if (active) setUser(me)
      })
      .catch(() => {
        // Fall back to decoded JWT claims if /me is unavailable.
        if (active && !user) {
          const claims = decodeToken(token)
          if (claims) setUser(claims)
        }
      })
      .finally(() => active && setLoading(false))
    return () => {
      active = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token])

  const applyToken = useCallback((newToken, maybeUser) => {
    localStorage.setItem(TOKEN_KEY, newToken)
    setToken(newToken)
    if (maybeUser) setUser(maybeUser)
    else {
      const claims = decodeToken(newToken)
      if (claims) setUser(claims)
    }
  }, [])

  const login = useCallback(
    async (credentials) => {
      const data = await authApi.login(credentials)
      applyToken(data.token, data.user)
      return data
    },
    [applyToken]
  )

  const register = useCallback(
    async (payload) => {
      const data = await authApi.register(payload)
      if (data.token) applyToken(data.token, data.user)
      return data
    },
    [applyToken]
  )

  const logout = useCallback(() => {
    localStorage.removeItem(TOKEN_KEY)
    setToken(null)
    setUser(null)
  }, [])

  // Normalise role lookup — accept role, roles[], or claim shapes.
  const role = user?.role || (Array.isArray(user?.roles) ? user.roles[0] : undefined)

  const value = {
    token,
    user,
    role,
    loading,
    isAuthenticated: Boolean(token),
    login,
    register,
    logout,
    setUser,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within an AuthProvider')
  return ctx
}
