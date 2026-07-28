import { useNavigate } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import { Minus, Plus, Trash2, Store } from 'lucide-react'
import { useCart } from '../store/CartContext'
import EmptyState from '../components/EmptyState'
import { rupees, rupeesP, emojiFor } from '../lib/format'

// Cart with animated line items (enter/exit), quantity steppers, and a summary
// (subtotal + delivery + taxes + total). Currency in rupees.
const DELIVERY_FEE = 39

export default function Cart() {
  const { cart, subtotal, count, setQuantity, removeItem, clear } = useCart()
  const navigate = useNavigate()

  if (count === 0) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-16">
        <EmptyState emoji="🛒" title="Your cart is empty" message="Add some delicious dishes to get started." actionLabel="Browse restaurants" actionTo="/restaurants" />
      </div>
    )
  }

  const taxes = Math.round(subtotal * 0.05)
  const total = subtotal + DELIVERY_FEE + taxes

  return (
    <div className="mx-auto max-w-3xl px-4 py-8">
      <div className="mb-2 flex items-center justify-between">
        <h1 className="font-display text-3xl font-bold text-gray-900">Your cart</h1>
        <button onClick={clear} className="btn-ghost text-red-600">
          <Trash2 className="h-4 w-4" /> Clear
        </button>
      </div>

      {cart.restaurantName && (
        <p className="mb-4 flex items-center gap-1.5 text-sm text-gray-500">
          <Store className="h-4 w-4 text-brand-500" /> Ordering from{' '}
          <span className="font-semibold text-gray-700">{cart.restaurantName}</span>
        </p>
      )}

      <div className="space-y-3">
        <AnimatePresence initial={false}>
          {cart.items.map((item) => (
            <motion.div
              key={item.id}
              layout
              initial={{ opacity: 0, height: 0, marginBottom: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              exit={{ opacity: 0, x: -40, height: 0, marginBottom: 0 }}
              transition={{ duration: 0.25 }}
              className="card flex items-center justify-between gap-4 overflow-hidden p-4"
            >
              <div className="flex min-w-0 items-center gap-3">
                <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-brand-50 text-2xl">
                  {emojiFor(item.name)}
                </span>
                <div className="min-w-0">
                  <h4 className="truncate font-semibold text-gray-900">{item.name}</h4>
                  <p className="text-sm text-gray-500">{rupees(item.price)} each</p>
                </div>
              </div>

              <div className="flex items-center gap-3">
                <div className="flex items-center rounded-xl border border-gray-200 bg-white">
                  <button
                    className="grid h-8 w-8 place-items-center text-gray-600 hover:text-brand-600"
                    onClick={() => setQuantity(item.id, item.quantity - 1)}
                    aria-label="Decrease"
                  >
                    <Minus className="h-4 w-4" />
                  </button>
                  <span className="w-7 text-center text-sm font-semibold">{item.quantity}</span>
                  <button
                    className="grid h-8 w-8 place-items-center text-gray-600 hover:text-brand-600"
                    onClick={() => setQuantity(item.id, item.quantity + 1)}
                    aria-label="Increase"
                  >
                    <Plus className="h-4 w-4" />
                  </button>
                </div>
                <span className="w-20 text-right font-semibold text-gray-900">
                  {rupees(item.price * item.quantity)}
                </span>
                <button
                  onClick={() => removeItem(item.id)}
                  className="text-gray-400 transition hover:text-red-600"
                  title="Remove"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>

      <motion.div layout className="card mt-6 p-5">
        <h2 className="mb-3 font-display font-semibold text-gray-800">Bill summary</h2>
        <Row label="Subtotal" value={subtotal} />
        <Row label="Delivery fee" value={DELIVERY_FEE} />
        <Row label="Taxes & charges (5%)" value={taxes} />
        <div className="my-3 border-t border-dashed border-gray-200" />
        <Row label="To pay" value={total} bold />
        <button className="btn-primary mt-5 w-full" onClick={() => navigate('/checkout')}>
          Proceed to checkout
        </button>
      </motion.div>
    </div>
  )
}

function Row({ label, value, bold }) {
  return (
    <div className={`flex justify-between py-1 ${bold ? 'text-lg font-bold text-gray-900' : 'text-sm text-gray-600'}`}>
      <span>{label}</span>
      <span>{bold ? rupeesP(value) : rupees(value)}</span>
    </div>
  )
}
