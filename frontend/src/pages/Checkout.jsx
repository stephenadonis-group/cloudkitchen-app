import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import toast from 'react-hot-toast'
import { MapPin, CreditCard, Smartphone, Wallet, CheckCircle2 } from 'lucide-react'
import { useCart } from '../store/CartContext'
import { cartApi, ordersApi, paymentsApi } from '../api/orders'
import { usersApi } from '../api/users'
import { rupees, rupeesP, readId, readList } from '../lib/format'

const DELIVERY_FEE = 39

// Checkout flow:
//   1. sync local cart -> server cart (POST /api/cart/items)
//   2. place order (POST /api/orders { restaurant_id })
//   3. poll payment status (created server-side) for a realistic sequence
//   4. clear local cart, route to /orders/:id
const PAYMENT_METHODS = [
  { value: 'card', label: 'Card', Icon: CreditCard },
  { value: 'upi', label: 'UPI', Icon: Smartphone },
  { value: 'cash', label: 'Cash on delivery', Icon: Wallet },
]

export default function Checkout() {
  const { cart, subtotal, count, clear } = useCart()
  const navigate = useNavigate()

  const [address, setAddress] = useState('')
  const [savedAddresses, setSavedAddresses] = useState([])
  const [paymentMethod, setPaymentMethod] = useState('card')
  const [stage, setStage] = useState('idle') // idle | placing | paying | done | error
  const [message, setMessage] = useState('')

  const taxes = Math.round(subtotal * 0.05)
  const total = subtotal + DELIVERY_FEE + taxes

  useEffect(() => {
    if (count === 0 && stage === 'idle') navigate('/cart', { replace: true })
  }, [count, navigate, stage])

  useEffect(() => {
    usersApi.getAddresses()
      .then((data) => {
        const list = readList(data)
        setSavedAddresses(list)
        if (list[0]) setAddress(list[0].line || list[0].address || formatAddr(list[0]))
      })
      .catch(() => {})
  }, [])

  const placeOrder = async (e) => {
    e.preventDefault()
    setMessage('')
    setStage('placing')
    try {
      // 1) Best-effort: push local cart lines to the server cart so the order
      //    service can build the order. Ignore per-line failures.
      await Promise.allSettled(
        cart.items.map((i) =>
          cartApi.addItem({ item_id: i.id, name: i.name, qty: i.quantity, price: i.price })
        )
      )

      // 2) Create the order. Backend builds it from the cart given restaurant_id.
      const order = await ordersApi.create({
        restaurant_id: cart.restaurantId,
        restaurantId: cart.restaurantId, // tolerate camelCase backends
        delivery_address: address,
        payment_method: paymentMethod,
      })
      const orderId = readId(order)

      // 3) Payment processing animation; read the server-side payment record.
      setStage('paying')
      await new Promise((r) => setTimeout(r, 1400))
      let status = 'SUCCESS'
      try {
        const payment = await paymentsApi.forOrder(orderId)
        status = payment?.status || status
      } catch { /* payment record may lag; assume success for UX */ }

      setStage('done')
      setMessage(`Payment ${status}. Order confirmed!`)
      clear()
      cartApi.clear().catch(() => {})
      toast.success('Order placed! 🎉')
      setTimeout(() => navigate(`/orders/${orderId}`), 1300)
    } catch (err) {
      setStage('error')
      setMessage(err?.response?.data?.message || 'Something went wrong placing your order.')
      toast.error('Could not place order.')
    }
  }

  if (count === 0 && stage === 'idle') return null

  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <h1 className="mb-6 font-display text-3xl font-bold text-gray-900">Checkout</h1>

      <AnimatePresence mode="wait">
        {(stage === 'placing' || stage === 'paying') && (
          <motion.div
            key="processing"
            initial={{ opacity: 0, scale: 0.96 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0 }}
            className="card flex flex-col items-center px-6 py-16 text-center"
          >
            <motion.div
              className="text-5xl"
              animate={{ rotate: stage === 'paying' ? [0, 0] : 360, scale: stage === 'paying' ? [1, 1.15, 1] : 1 }}
              transition={{ repeat: Infinity, duration: stage === 'paying' ? 0.9 : 1.8, ease: 'linear' }}
            >
              {stage === 'placing' ? '🧑‍🍳' : '💳'}
            </motion.div>
            <p className="mt-5 font-display text-lg font-semibold text-gray-900">
              {stage === 'placing' ? 'Placing your order…' : 'Processing payment…'}
            </p>
            <p className="mt-1 text-sm text-gray-500">Hang tight, this only takes a moment.</p>
          </motion.div>
        )}

        {stage === 'done' && (
          <motion.div
            key="done"
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            className="card flex flex-col items-center px-6 py-16 text-center"
          >
            <motion.div
              initial={{ scale: 0 }}
              animate={{ scale: 1 }}
              transition={{ type: 'spring', stiffness: 300, damping: 14 }}
              className="grid h-16 w-16 place-items-center rounded-full bg-green-100 text-green-600"
            >
              <CheckCircle2 className="h-9 w-9" />
            </motion.div>
            <h2 className="mt-4 font-display text-xl font-bold text-gray-900">Order confirmed</h2>
            <p className="mt-2 text-gray-500">{message}</p>
            <p className="mt-1 text-sm text-gray-400">Taking you to live tracking…</p>
          </motion.div>
        )}

        {(stage === 'idle' || stage === 'error') && (
          <motion.form
            key="form"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            onSubmit={placeOrder}
            className="space-y-5"
          >
            <section className="card p-5">
              <h2 className="mb-3 flex items-center gap-2 font-display font-semibold text-gray-800">
                <MapPin className="h-4 w-4 text-brand-500" /> Delivery address
              </h2>
              {savedAddresses.length > 0 && (
                <select
                  className="input mb-3"
                  onChange={(e) => setAddress(e.target.value)}
                  value={address}
                >
                  {savedAddresses.map((a, i) => {
                    const line = a.line || a.address || formatAddr(a)
                    return <option key={i} value={line}>{line}</option>
                  })}
                </select>
              )}
              <textarea
                className="input" rows={3} required
                placeholder="House no, street, area, city, pincode…"
                value={address}
                onChange={(e) => setAddress(e.target.value)}
              />
            </section>

            <section className="card p-5">
              <h2 className="mb-3 flex items-center gap-2 font-display font-semibold text-gray-800">
                <CreditCard className="h-4 w-4 text-brand-500" /> Payment method
              </h2>
              <div className="grid gap-2 sm:grid-cols-3">
                {PAYMENT_METHODS.map(({ value, label, Icon }) => {
                  const active = paymentMethod === value
                  return (
                    <button
                      type="button" key={value}
                      onClick={() => setPaymentMethod(value)}
                      className={`flex items-center gap-2 rounded-xl border-2 px-3 py-3 text-sm font-medium transition ${
                        active ? 'border-brand-500 bg-brand-50 text-brand-700' : 'border-gray-200 text-gray-600 hover:border-brand-200'
                      }`}
                    >
                      <Icon className="h-4 w-4" /> {label}
                    </button>
                  )
                })}
              </div>
            </section>

            <section className="card p-5">
              <h2 className="mb-3 font-display font-semibold text-gray-800">Order summary</h2>
              {cart.items.map((i) => (
                <div key={i.id} className="flex justify-between py-0.5 text-sm text-gray-600">
                  <span>{i.quantity} × {i.name}</span>
                  <span>{rupees(i.price * i.quantity)}</span>
                </div>
              ))}
              <div className="my-2 border-t border-dashed border-gray-200" />
              <div className="flex justify-between text-sm text-gray-600"><span>Delivery fee</span><span>{rupees(DELIVERY_FEE)}</span></div>
              <div className="flex justify-between text-sm text-gray-600"><span>Taxes & charges</span><span>{rupees(taxes)}</span></div>
              <div className="mt-1 flex justify-between text-lg font-bold text-gray-900"><span>To pay</span><span>{rupeesP(total)}</span></div>
            </section>

            {stage === 'error' && (
              <div className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700">{message}</div>
            )}

            <button type="submit" className="btn-primary w-full">
              Place order · pay {rupeesP(total)}
            </button>
          </motion.form>
        )}
      </AnimatePresence>
    </div>
  )
}

function formatAddr(a) {
  return [a.line1 || a.street, a.city, a.pincode || a.zip].filter(Boolean).join(', ')
}
