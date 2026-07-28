import { Routes, Route, Navigate, useLocation, Link } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { Toaster } from 'react-hot-toast'
import Navbar from './components/Navbar'
import ProtectedRoute from './components/ProtectedRoute'
import PageTransition from './components/PageTransition'

import Login from './pages/Login'
import Register from './pages/Register'
import Restaurants from './pages/Restaurants'
import RestaurantMenu from './pages/RestaurantMenu'
import Cart from './pages/Cart'
import Checkout from './pages/Checkout'
import Orders from './pages/Orders'
import OrderTrack from './pages/OrderTrack'
import Profile from './pages/Profile'
import RestaurantAdmin from './pages/RestaurantAdmin'
import AdminDashboard from './pages/AdminDashboard'

// App shell: persistent navbar + routed pages with animated transitions.
// A single branded Toaster is mounted here. AnimatePresence cross-fades pages
// on navigation; each page is wrapped in PageTransition.
export default function App() {
  const location = useLocation()

  return (
    <div className="min-h-screen">
      <Navbar />
      <Toaster
        position="top-center"
        toastOptions={{
          duration: 3000,
          style: {
            borderRadius: '14px',
            background: '#fff',
            color: '#1f2937',
            boxShadow: '0 8px 30px -8px rgba(17,24,39,0.18)',
            border: '1px solid #f3f4f6',
            fontWeight: 500,
            fontSize: '14px',
          },
          success: { iconTheme: { primary: '#f97316', secondary: '#fff' } },
          error: { iconTheme: { primary: '#ef4444', secondary: '#fff' } },
        }}
      />
      <main>
        <AnimatePresence mode="wait">
          <Routes location={location} key={location.pathname}>
            {/* Public */}
            <Route path="/" element={<Navigate to="/restaurants" replace />} />
            <Route path="/login" element={<PageTransition><Login /></PageTransition>} />
            <Route path="/register" element={<PageTransition><Register /></PageTransition>} />
            <Route path="/restaurants" element={<PageTransition><Restaurants /></PageTransition>} />
            <Route path="/restaurants/:rid" element={<PageTransition><RestaurantMenu /></PageTransition>} />
            <Route path="/cart" element={<PageTransition><Cart /></PageTransition>} />

            {/* Authenticated (any role) */}
            <Route
              path="/checkout"
              element={<ProtectedRoute><PageTransition><Checkout /></PageTransition></ProtectedRoute>}
            />
            <Route
              path="/orders"
              element={<ProtectedRoute><PageTransition><Orders /></PageTransition></ProtectedRoute>}
            />
            <Route
              path="/orders/:id"
              element={<ProtectedRoute><PageTransition><OrderTrack /></PageTransition></ProtectedRoute>}
            />
            <Route
              path="/profile"
              element={<ProtectedRoute><PageTransition><Profile /></PageTransition></ProtectedRoute>}
            />

            {/* Restaurant admin */}
            <Route
              path="/admin/restaurant"
              element={
                <ProtectedRoute roles={['restaurant-admin', 'admin']}>
                  <PageTransition><RestaurantAdmin /></PageTransition>
                </ProtectedRoute>
              }
            />

            {/* Platform admin */}
            <Route
              path="/admin"
              element={
                <ProtectedRoute roles={['admin']}>
                  <PageTransition><AdminDashboard /></PageTransition>
                </ProtectedRoute>
              }
            />

            {/* Fallback */}
            <Route path="*" element={<PageTransition><NotFound /></PageTransition>} />
          </Routes>
        </AnimatePresence>
      </main>
    </div>
  )
}

function NotFound() {
  return (
    <div className="mx-auto flex max-w-xl flex-col items-center px-4 py-24 text-center">
      <motion.div
        className="text-7xl"
        animate={{ rotate: [0, -8, 8, 0] }}
        transition={{ repeat: Infinity, duration: 3, ease: 'easeInOut' }}
      >
        🍕
      </motion.div>
      <h1 className="mt-4 bg-gradient-to-br from-brand-500 to-brand-700 bg-clip-text text-6xl font-extrabold text-transparent">
        404
      </h1>
      <p className="mt-3 text-gray-500">Looks like this dish is off the menu.</p>
      <Link to="/restaurants" className="btn-primary mt-6">Back to restaurants</Link>
    </div>
  )
}
