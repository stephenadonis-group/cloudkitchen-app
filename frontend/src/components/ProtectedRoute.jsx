import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '../store/AuthContext'
import Loader from './Loader'

// Route guard. Requires authentication, and optionally a role from `roles`.
// While the auth state is still hydrating we show a loader to avoid a flash
// redirect to /login.
export default function ProtectedRoute({ children, roles }) {
  const { isAuthenticated, role, loading } = useAuth()
  const location = useLocation()

  if (loading) return <Loader label="Checking session…" />

  if (!isAuthenticated) {
    return <Navigate to="/login" replace state={{ from: location }} />
  }

  if (roles && roles.length > 0 && !roles.includes(role)) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-24 text-center">
        <div className="text-6xl">🔒</div>
        <h1 className="mt-4 font-display text-2xl font-bold text-gray-900">Access denied</h1>
        <p className="mt-2 text-gray-500">
          You need one of these roles to view this page: {roles.join(', ')}.
        </p>
      </div>
    )
  }

  return children
}
