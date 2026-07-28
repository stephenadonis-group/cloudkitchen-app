import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Plus, Check } from 'lucide-react'
import { rupees, emojiFor } from '../lib/format'

// A single menu item with a satisfying add-to-cart animation.
// `available === false` disables the Add button. `onAdd(item)` is called on tap.
export default function MenuItemCard({ item, onAdd, index = 0 }) {
  const [added, setAdded] = useState(false)
  const available = item.available !== false
  // Heuristic veg/nonveg dot: backend may send is_veg; otherwise guess by name.
  const veg =
    item.is_veg ??
    item.veg ??
    !/(chicken|mutton|beef|fish|prawn|egg|lamb|pork|meat)/i.test(item.name || '')

  const handleAdd = () => {
    if (!available) return
    onAdd?.(item)
    setAdded(true)
    setTimeout(() => setAdded(false), 1100)
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, delay: Math.min(index * 0.04, 0.3) }}
      className="card flex items-center justify-between gap-4 p-4 transition-shadow hover:shadow-lift"
    >
      <div className="flex min-w-0 items-start gap-3">
        <span
          className={`mt-1 grid h-4 w-4 shrink-0 place-items-center rounded-sm border-2 ${
            veg ? 'border-green-600' : 'border-red-600'
          }`}
          title={veg ? 'Veg' : 'Non-veg'}
        >
          <span className={`h-2 w-2 rounded-full ${veg ? 'bg-green-600' : 'bg-red-600'}`} />
        </span>
        <div className="min-w-0">
          <h4 className="font-display font-semibold text-gray-900">{item.name}</h4>
          {item.description && (
            <p className="mt-0.5 line-clamp-2 text-sm text-gray-500">{item.description}</p>
          )}
          <p className="mt-1.5 font-semibold text-gray-900">{rupees(item.price)}</p>
        </div>
      </div>

      <div className="flex shrink-0 flex-col items-center gap-2">
        <span className="text-3xl">{emojiFor(item.name || '')}</span>
        {available ? (
          <motion.button
            onClick={handleAdd}
            whileTap={{ scale: 0.9 }}
            className={`btn relative w-24 overflow-hidden ${
              added
                ? 'bg-green-500 text-white shadow-soft'
                : 'btn-primary'
            }`}
          >
            <AnimatePresence mode="wait" initial={false}>
              {added ? (
                <motion.span
                  key="added"
                  initial={{ y: 12, opacity: 0 }}
                  animate={{ y: 0, opacity: 1 }}
                  exit={{ y: -12, opacity: 0 }}
                  className="flex items-center gap-1"
                >
                  <Check className="h-4 w-4" /> Added
                </motion.span>
              ) : (
                <motion.span
                  key="add"
                  initial={{ y: 12, opacity: 0 }}
                  animate={{ y: 0, opacity: 1 }}
                  exit={{ y: -12, opacity: 0 }}
                  className="flex items-center gap-1"
                >
                  <Plus className="h-4 w-4" /> Add
                </motion.span>
              )}
            </AnimatePresence>
          </motion.button>
        ) : (
          <span className="badge-muted">Sold out</span>
        )}
      </div>
    </motion.div>
  )
}
