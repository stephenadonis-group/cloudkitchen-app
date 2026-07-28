import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import { ChevronRight, Receipt } from 'lucide-react'
import { ordersApi } from '../api/orders'
import StatusBadge from '../components/StatusBadge'
import EmptyState from '../components/EmptyState'
import { ListSkeleton } from '../components/Skeleton'
import { rupees, readId, readList, emojiFor } from '../lib/format'

// Past orders list. Each card links to live tracking.
export default function Orders() {
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    ordersApi.list()
      .then((data) => active && setOrders(readList(data)))
      .catch(() => active && setError('Could not load your orders.'))
      .finally(() => active && setLoading(false))
    return () => { active = false }
  }, [])

  return (
    <div className="mx-auto max-w-3xl px-4 py-8">
      <h1 className="mb-6 font-display text-3xl font-bold text-gray-900">Your orders</h1>

      {loading ? (
        <ListSkeleton count={4} />
      ) : error ? (
        <EmptyState emoji="⚠️" title="Couldn't load" message={error} />
      ) : orders.length === 0 ? (
        <EmptyState emoji="🧾" title="No orders yet" message="When you place an order it'll show up here." actionLabel="Order now" actionTo="/restaurants" />
      ) : (
        <div className="space-y-3">
          {orders.map((o, i) => {
            const id = readId(o)
            const itemCount = (o.items || o.lineItems || []).length
            const created = o.created_at || o.createdAt
            const name = o.restaurant_name || o.restaurantName || `Order`
            return (
              <motion.div
                key={id}
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: Math.min(i * 0.05, 0.3) }}
              >
                <Link
                  to={`/orders/${id}`}
                  className="card flex items-center justify-between gap-4 p-4 transition hover:shadow-lift"
                >
                  <div className="flex min-w-0 items-center gap-3">
                    <span className="grid h-12 w-12 shrink-0 place-items-center rounded-xl bg-brand-50 text-2xl">
                      {itemCount ? emojiFor(name + id) : <Receipt className="h-5 w-5 text-brand-500" />}
                    </span>
                    <div className="min-w-0">
                      <p className="font-display font-semibold text-gray-900">
                        {name} · #{String(id).slice(-6)}
                      </p>
                      <p className="truncate text-sm text-gray-500">
                        {created ? new Date(created).toLocaleString() : ''}
                        {itemCount ? ` · ${itemCount} item${itemCount > 1 ? 's' : ''}` : ''}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-3 text-right">
                    <div>
                      <StatusBadge status={o.status} />
                      {o.total != null && (
                        <p className="mt-1 font-semibold text-gray-900">{rupees(o.total)}</p>
                      )}
                    </div>
                    <ChevronRight className="h-5 w-5 shrink-0 text-gray-300" />
                  </div>
                </Link>
              </motion.div>
            )
          })}
        </div>
      )}
    </div>
  )
}
