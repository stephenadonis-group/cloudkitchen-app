import { useEffect, useState, useCallback } from 'react'
import { useParams, Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import {
  ArrowLeft, ClipboardCheck, CheckCircle2, ChefHat, Bike, PackageCheck, User,
} from 'lucide-react'
import { ordersApi, paymentsApi, deliveriesApi } from '../api/orders'
import StatusBadge from '../components/StatusBadge'
import Loader from '../components/Loader'
import { rupees, rupeesP, readId } from '../lib/format'

// THE realtime centerpiece. Polls order + payment + delivery every ~3.5s.
// Renders an animated horizontal timeline with a glowing "live" current step,
// a progress fill, and a delivery scooter that rides along the track.
const STEPS = [
  { key: 'PLACED', label: 'Placed', Icon: ClipboardCheck },
  { key: 'CONFIRMED', label: 'Confirmed', Icon: CheckCircle2 },
  { key: 'PREPARING', label: 'Preparing', Icon: ChefHat },
  { key: 'OUT_FOR_DELIVERY', label: 'On the way', Icon: Bike },
  { key: 'DELIVERED', label: 'Delivered', Icon: PackageCheck },
]

// Map various backend statuses onto a step index.
function stepIndex(status) {
  const s = String(status || '').toUpperCase()
  if (s === 'DELIVERED') return 4
  if (s === 'OUT_FOR_DELIVERY' || s === 'ASSIGNED') return 3
  if (s === 'PREPARING' || s === 'READY' || s === 'ACCEPTED') return 2
  if (s === 'CONFIRMED' || s === 'PAID' || s === 'SUCCESS') return 1
  return 0 // PLACED / PENDING / unknown
}

export default function OrderTrack() {
  const { id } = useParams()
  const [order, setOrder] = useState(null)
  const [tracking, setTracking] = useState(null)
  const [payment, setPayment] = useState(null)
  const [delivery, setDelivery] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const refresh = useCallback(async () => {
    try {
      const [o, t] = await Promise.all([
        ordersApi.get(id),
        ordersApi.track(id).catch(() => null),
      ])
      setOrder(o)
      setTracking(t)
      paymentsApi.forOrder(id).then(setPayment).catch(() => {})
      deliveriesApi.forOrder(id).then(setDelivery).catch(() => {})
    } catch {
      setError('Could not load this order.')
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => { refresh() }, [id, refresh])

  // Poll every 3.5s until terminal.
  useEffect(() => {
    const status = String(tracking?.status || delivery?.status || order?.status || '').toUpperCase()
    if (status === 'DELIVERED' || status === 'CANCELLED') return
    const t = setInterval(refresh, 3500)
    return () => clearInterval(t)
  }, [tracking?.status, delivery?.status, order?.status, refresh])

  if (loading) return <Loader label="Loading your order…" fullscreen />
  if (error) return <div className="mx-auto max-w-2xl px-4 py-12"><p className="text-center text-gray-500">{error}</p></div>

  // Prefer the most-advanced signal among order/track/delivery.
  const statuses = [order?.status, tracking?.status, delivery?.status]
  const current = Math.max(...statuses.map(stepIndex), 0)
  const isCancelled = statuses.some((s) => String(s || '').toUpperCase() === 'CANCELLED')
  const headStatus = STEPS[current]?.key
  const items = order?.items || order?.lineItems || []
  const progressPct = (current / (STEPS.length - 1)) * 100

  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <Link to="/orders" className="inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:underline">
        <ArrowLeft className="h-4 w-4" /> All orders
      </Link>

      <div className="mt-3 flex items-center justify-between">
        <h1 className="font-display text-2xl font-bold text-gray-900">
          Order #{String(id).slice(-6)}
        </h1>
        <StatusBadge status={isCancelled ? 'CANCELLED' : headStatus} />
      </div>

      {/* Live tracking */}
      <div className="card mt-6 overflow-hidden p-5">
        <div className="mb-5 flex items-center justify-between">
          <h2 className="font-display font-semibold text-gray-800">Live tracking</h2>
          {!isCancelled && current < 4 && (
            <span className="flex items-center gap-1.5 text-xs font-semibold text-green-600">
              <span className="relative flex h-2.5 w-2.5">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-400 opacity-75" />
                <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-green-500" />
              </span>
              LIVE
            </span>
          )}
        </div>

        {isCancelled ? (
          <p className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700">This order was cancelled.</p>
        ) : (
          <>
            {/* Horizontal timeline */}
            <div className="relative px-2 pt-6">
              {/* track */}
              <div className="absolute left-6 right-6 top-9 h-1 rounded-full bg-gray-200" />
              <motion.div
                className="absolute left-6 top-9 h-1 rounded-full bg-gradient-to-r from-brand-400 to-brand-600"
                initial={false}
                animate={{ width: `calc((100% - 3rem) * ${progressPct / 100})` }}
                transition={{ type: 'spring', stiffness: 80, damping: 18 }}
              />
              {/* scooter riding the track */}
              <motion.div
                className="absolute top-2 text-2xl"
                initial={false}
                animate={{ left: `calc(1rem + (100% - 3rem) * ${progressPct / 100})` }}
                transition={{ type: 'spring', stiffness: 80, damping: 18 }}
                style={{ transform: 'translateX(-50%)' }}
              >
                <motion.span animate={{ y: [0, -2, 0] }} transition={{ repeat: Infinity, duration: 0.6 }}>
                  🛵
                </motion.span>
              </motion.div>

              <div className="relative flex justify-between">
                {STEPS.map((step, i) => {
                  const done = i < current
                  const active = i === current
                  const { Icon } = step
                  return (
                    <div key={step.key} className="flex w-14 flex-col items-center">
                      <motion.span
                        initial={false}
                        animate={active ? { scale: [1, 1.12, 1] } : { scale: 1 }}
                        transition={active ? { repeat: Infinity, duration: 1.6 } : {}}
                        className={`grid h-9 w-9 place-items-center rounded-full border-2 transition-colors ${
                          done || active
                            ? 'border-brand-500 bg-brand-500 text-white'
                            : 'border-gray-200 bg-white text-gray-300'
                        } ${active ? 'animate-pulse-ring' : ''}`}
                      >
                        <Icon className="h-4 w-4" />
                      </motion.span>
                      <span className={`mt-2 text-center text-[11px] font-medium leading-tight ${done || active ? 'text-gray-900' : 'text-gray-400'}`}>
                        {step.label}
                      </span>
                    </div>
                  )
                })}
              </div>
            </div>

            <p className="mt-6 text-center text-sm text-gray-500">
              {current >= 4
                ? 'Delivered — enjoy your meal! 🎉'
                : current === 3
                ? 'Your rider is on the way 🛵'
                : current === 2
                ? 'The kitchen is preparing your food 🧑‍🍳'
                : current === 1
                ? 'Payment confirmed, sending to kitchen…'
                : 'Order received, awaiting confirmation…'}
              {tracking?.eta && current < 4 && ` · ETA ${tracking.eta}`}
            </p>
          </>
        )}
      </div>

      {/* Payment + delivery */}
      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <div className="card p-5">
          <h3 className="font-display font-semibold text-gray-800">Payment</h3>
          <div className="mt-2 flex items-center gap-2">
            <StatusBadge status={payment?.status || (current >= 1 ? 'SUCCESS' : 'PENDING')} />
            {payment?.method && <span className="text-sm capitalize text-gray-500">{payment.method}</span>}
          </div>
          {payment?.amount != null && (
            <p className="mt-2 text-sm text-gray-500">Amount: {rupeesP(payment.amount)}</p>
          )}
        </div>
        <div className="card p-5">
          <h3 className="font-display font-semibold text-gray-800">Delivery</h3>
          {delivery ? (
            <div className="mt-2 space-y-2">
              <StatusBadge status={delivery.status} />
              <p className="flex items-center gap-1.5 text-sm text-gray-500">
                <User className="h-3.5 w-3.5" />
                {delivery.agent_id || delivery.agentName
                  ? `Rider ${delivery.agentName || `#${String(delivery.agent_id).slice(-4)}`}`
                  : 'Awaiting rider assignment'}
              </p>
            </div>
          ) : (
            <p className="mt-2 text-sm text-gray-500">Awaiting rider assignment.</p>
          )}
        </div>
      </div>

      {/* Items */}
      {items.length > 0 && (
        <div className="card mt-4 p-5">
          <h2 className="mb-3 font-display font-semibold text-gray-800">Items</h2>
          {items.map((i, idx) => (
            <div key={readId(i) ?? i.item_id ?? idx} className="flex justify-between py-1 text-sm text-gray-600">
              <span>{i.qty ?? i.quantity ?? 1} × {i.name}</span>
              {i.price != null && <span>{rupees(Number(i.price) * (i.qty ?? i.quantity ?? 1))}</span>}
            </div>
          ))}
          {order?.total != null && (
            <div className="mt-2 flex justify-between border-t border-dashed border-gray-200 pt-2 font-bold text-gray-900">
              <span>Total</span><span>{rupeesP(order.total)}</span>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
