import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { Store, Package, Bike, TrendingUp, IndianRupee } from 'lucide-react'
import { restaurantsApi } from '../api/restaurants'
import { ordersApi } from '../api/orders'
import Loader from '../components/Loader'
import StatusBadge from '../components/StatusBadge'
import { rupees, readId, readList } from '../lib/format'

// Platform-admin dashboard. Pulls live counts from the available endpoints and
// derives a few headline stats (revenue, recent orders) gracefully.
export default function AdminDashboard() {
  const [data, setData] = useState({ restaurants: [], orders: [] })
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    Promise.all([
      restaurantsApi.list().catch(() => []),
      ordersApi.list().catch(() => []),
    ]).then(([r, o]) => {
      setData({ restaurants: readList(r), orders: readList(o) })
      setLoading(false)
    })
  }, [])

  if (loading) return <Loader label="Loading dashboard…" fullscreen />

  const { restaurants, orders } = data
  const revenue = orders.reduce((sum, o) => sum + (Number(o.total) || 0), 0)
  const active = orders.filter((o) => !['DELIVERED', 'CANCELLED'].includes(String(o.status || '').toUpperCase())).length
  const recent = [...orders].slice(-6).reverse()

  const stats = [
    { label: 'Restaurants', value: restaurants.length, Icon: Store, tint: 'from-orange-400 to-brand-600' },
    { label: 'Total orders', value: orders.length, Icon: Package, tint: 'from-sky-400 to-blue-600' },
    { label: 'Active orders', value: active, Icon: Bike, tint: 'from-violet-400 to-fuchsia-600' },
    { label: 'Revenue', value: rupees(revenue), Icon: IndianRupee, tint: 'from-emerald-400 to-green-600' },
  ]

  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      <h1 className="mb-1 font-display text-3xl font-bold text-gray-900">Admin dashboard</h1>
      <p className="mb-6 flex items-center gap-1.5 text-gray-500"><TrendingUp className="h-4 w-4 text-brand-500" /> Platform overview</p>

      {/* Stat cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {stats.map((s, i) => (
          <motion.div
            key={s.label}
            initial={{ opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: i * 0.06 }}
            className="card overflow-hidden p-5"
          >
            <span className={`grid h-11 w-11 place-items-center rounded-xl bg-gradient-to-br ${s.tint} text-white shadow-soft`}>
              <s.Icon className="h-5 w-5" />
            </span>
            <p className="mt-3 font-display text-3xl font-bold text-gray-900">{s.value ?? '—'}</p>
            <p className="text-sm text-gray-500">{s.label}</p>
          </motion.div>
        ))}
      </div>

      {/* Recent orders + restaurants */}
      <div className="mt-8 grid gap-6 lg:grid-cols-2">
        <div className="card p-5">
          <h2 className="mb-3 font-display font-semibold text-gray-800">Recent orders</h2>
          {recent.length === 0 ? (
            <p className="text-sm text-gray-500">No orders visible.</p>
          ) : (
            <div className="space-y-2">
              {recent.map((o) => (
                <div key={readId(o)} className="flex items-center justify-between rounded-xl bg-gray-50 px-3 py-2.5 text-sm">
                  <span className="font-medium text-gray-700">#{String(readId(o)).slice(-6)}</span>
                  <div className="flex items-center gap-3">
                    <StatusBadge status={o.status} />
                    {o.total != null && <span className="font-semibold text-gray-900">{rupees(o.total)}</span>}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="card p-5">
          <h2 className="mb-3 font-display font-semibold text-gray-800">Restaurants</h2>
          {restaurants.length === 0 ? (
            <p className="text-sm text-gray-500">No restaurants yet.</p>
          ) : (
            <div className="space-y-2">
              {restaurants.slice(0, 6).map((r) => (
                <div key={readId(r)} className="flex items-center justify-between rounded-xl bg-gray-50 px-3 py-2.5 text-sm">
                  <span className="font-medium text-gray-700">{r.name}</span>
                  <span className="text-gray-400">{r.city || r.status || '—'}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
