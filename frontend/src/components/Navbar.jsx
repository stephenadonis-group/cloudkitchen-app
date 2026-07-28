import { useEffect, useRef, useState } from 'react'
import { Link, NavLink, useNavigate, useLocation } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import { ShoppingCart, Menu, X, User, LogOut, ChefHat, Store, LayoutDashboard, Package } from 'lucide-react'
import { useAuth } from '../store/AuthContext'
import { useCart } from '../store/CartContext'
import { initials } from '../lib/format'

// Sticky glassy navbar: animated logo, role-aware links with active underline,
// bouncing cart badge, avatar dropdown, and an animated mobile menu.
export default function Navbar() {
  const { isAuthenticated, user, role, logout } = useAuth()
  const { count } = useCart()
  const navigate = useNavigate()
  const location = useLocation()
  const [mobileOpen, setMobileOpen] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const menuRef = useRef(null)

  // Close menus on route change.
  useEffect(() => {
    setMobileOpen(false)
    setMenuOpen(false)
  }, [location.pathname])

  // Close avatar dropdown on outside click.
  useEffect(() => {
    const onClick = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) setMenuOpen(false)
    }
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [])

  const handleLogout = () => {
    logout()
    navigate('/login')
  }

  const links = [
    { to: '/restaurants', label: 'Restaurants', Icon: Store, show: true },
    { to: '/orders', label: 'Orders', Icon: Package, show: isAuthenticated },
    { to: '/admin/restaurant', label: 'My Restaurant', Icon: ChefHat, show: role === 'restaurant-admin' },
    { to: '/admin', label: 'Admin', Icon: LayoutDashboard, show: role === 'admin' },
  ].filter((l) => l.show)

  return (
    <header className="sticky top-0 z-40 glass">
      <nav className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
        {/* Logo */}
        <Link to="/" className="flex items-center gap-2 text-xl font-extrabold text-gray-900">
          <motion.span
            className="grid h-9 w-9 place-items-center rounded-xl bg-gradient-to-br from-brand-400 to-brand-600 text-lg text-white shadow-lift"
            whileHover={{ rotate: [0, -10, 10, 0], scale: 1.08 }}
            transition={{ duration: 0.5 }}
          >
            🍴
          </motion.span>
          <span className="font-display">
            Cloud<span className="text-brand-600">Kitchen</span>
          </span>
        </Link>

        {/* Desktop links */}
        <div className="hidden items-center gap-1 md:flex">
          {links.map(({ to, label }) => (
            <NavLink key={to} to={to} className="relative px-3 py-2 text-sm font-medium">
              {({ isActive }) => (
                <span className={isActive ? 'text-brand-700' : 'text-gray-600 hover:text-gray-900'}>
                  {label}
                  {isActive && (
                    <motion.span
                      layoutId="nav-underline"
                      className="absolute inset-x-2 -bottom-0.5 h-0.5 rounded-full bg-brand-500"
                    />
                  )}
                </span>
              )}
            </NavLink>
          ))}
        </div>

        {/* Right cluster */}
        <div className="flex items-center gap-2">
          {/* Cart with animated badge */}
          <Link
            to="/cart"
            className="relative grid h-10 w-10 place-items-center rounded-xl text-gray-700 transition hover:bg-brand-50 hover:text-brand-700"
            title="Cart"
          >
            <ShoppingCart className="h-5 w-5" />
            <AnimatePresence>
              {count > 0 && (
                <motion.span
                  key={count}
                  initial={{ scale: 0 }}
                  animate={{ scale: [1.4, 1] }}
                  exit={{ scale: 0 }}
                  transition={{ type: 'spring', stiffness: 500, damping: 15 }}
                  className="absolute -right-0.5 -top-0.5 grid h-5 min-w-[1.25rem] place-items-center rounded-full bg-brand-500 px-1 text-[11px] font-bold text-white shadow"
                >
                  {count}
                </motion.span>
              )}
            </AnimatePresence>
          </Link>

          {/* Auth area */}
          {isAuthenticated ? (
            <div className="relative hidden md:block" ref={menuRef}>
              <button
                onClick={() => setMenuOpen((o) => !o)}
                className="grid h-10 w-10 place-items-center rounded-full bg-gradient-to-br from-brand-500 to-brand-600 text-sm font-bold text-white shadow-lift transition hover:scale-105"
                title={user?.email}
              >
                {initials(user)}
              </button>
              <AnimatePresence>
                {menuOpen && (
                  <motion.div
                    initial={{ opacity: 0, y: -8, scale: 0.96 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    exit={{ opacity: 0, y: -8, scale: 0.96 }}
                    transition={{ duration: 0.16 }}
                    className="card absolute right-0 mt-2 w-52 overflow-hidden p-1.5"
                  >
                    <div className="px-3 py-2">
                      <p className="truncate text-sm font-semibold text-gray-900">{user?.name || 'Account'}</p>
                      <p className="truncate text-xs text-gray-500">{user?.email}</p>
                    </div>
                    <div className="my-1 border-t border-gray-100" />
                    <Link to="/profile" className="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-brand-50">
                      <User className="h-4 w-4" /> Profile
                    </Link>
                    <button
                      onClick={handleLogout}
                      className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-red-600 hover:bg-red-50"
                    >
                      <LogOut className="h-4 w-4" /> Logout
                    </button>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          ) : (
            <div className="hidden items-center gap-2 md:flex">
              <Link to="/login" className="btn-ghost">Login</Link>
              <Link to="/register" className="btn-primary">Sign up</Link>
            </div>
          )}

          {/* Mobile hamburger */}
          <button
            onClick={() => setMobileOpen((o) => !o)}
            className="grid h-10 w-10 place-items-center rounded-xl text-gray-700 hover:bg-brand-50 md:hidden"
            aria-label="Menu"
          >
            {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
          </button>
        </div>
      </nav>

      {/* Mobile slide-down menu */}
      <AnimatePresence>
        {mobileOpen && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
            className="overflow-hidden border-t border-gray-200/70 bg-white/95 backdrop-blur md:hidden"
          >
            <div className="space-y-1 px-4 py-3">
              {links.map(({ to, label, Icon }) => (
                <NavLink
                  key={to}
                  to={to}
                  className={({ isActive }) =>
                    `flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium ${
                      isActive ? 'bg-brand-50 text-brand-700' : 'text-gray-700 hover:bg-gray-50'
                    }`
                  }
                >
                  <Icon className="h-4 w-4" /> {label}
                </NavLink>
              ))}
              <div className="my-2 border-t border-gray-100" />
              {isAuthenticated ? (
                <>
                  <NavLink to="/profile" className="flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-gray-700 hover:bg-gray-50">
                    <User className="h-4 w-4" /> Profile
                  </NavLink>
                  <button onClick={handleLogout} className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-red-600 hover:bg-red-50">
                    <LogOut className="h-4 w-4" /> Logout
                  </button>
                </>
              ) : (
                <div className="flex gap-2 px-1 pt-1">
                  <Link to="/login" className="btn-secondary flex-1">Login</Link>
                  <Link to="/register" className="btn-primary flex-1">Sign up</Link>
                </div>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </header>
  )
}
