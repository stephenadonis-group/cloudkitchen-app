import { useEffect, useMemo, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import toast from 'react-hot-toast'
import { Star, MapPin, Clock, ShoppingCart } from 'lucide-react'
import { restaurantsApi } from '../api/restaurants'
import { menuApi } from '../api/menu'
import { useCart } from '../store/CartContext'
import MenuItemCard from '../components/MenuItemCard'
import EmptyState from '../components/EmptyState'
import Loader from '../components/Loader'
import {
  gradientFor, emojiFor, fauxRating, deliveryTime, rupees, readId,
} from '../lib/format'

// Restaurant detail: banner header, sticky category tabs, items grouped by
// category, and an animated sticky "View Cart" bar at the bottom.
export default function RestaurantMenu() {
  const { rid } = useParams()
  const { addItem, count, subtotal } = useCart()

  const [restaurant, setRestaurant] = useState(null)
  const [categories, setCategories] = useState([])
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [activeCat, setActiveCat] = useState(null)

  useEffect(() => {
    let active = true
    setLoading(true)
    Promise.all([restaurantsApi.get(rid), menuApi.forRestaurant(rid)])
      .then(([r, m]) => {
        if (!active) return
        setRestaurant(r)
        // Menu endpoint returns { categories, items } but tolerate a flat array.
        if (Array.isArray(m)) {
          setItems(m)
          setCategories([])
        } else {
          setCategories(m.categories || [])
          setItems(m.items || [])
        }
      })
      .catch(() => active && setError('Could not load this restaurant.'))
      .finally(() => active && setLoading(false))
    return () => { active = false }
  }, [rid])

  // Group items by category id; uncategorised items fall into "More".
  const groups = useMemo(() => {
    const catName = (id) => categories.find((c) => readId(c) === id)?.name
    const map = new Map()
    for (const it of items) {
      const cid = it.category_id ?? it.categoryId ?? null
      const key = cid ?? '__none'
      if (!map.has(key)) map.set(key, { id: key, name: catName(cid) || 'More', items: [] })
      map.get(key).items.push(it)
    }
    // Preserve declared category order first.
    const ordered = []
    for (const c of categories) {
      const g = map.get(readId(c))
      if (g) { ordered.push(g); map.delete(readId(c)) }
    }
    return [...ordered, ...map.values()]
  }, [items, categories])

  const handleAdd = (item) => {
    const ok = addItem(item, restaurant)
    if (!ok) {
      if (window.confirm('Your cart has items from another restaurant. Clear it and add this item?')) {
        addItem(item, restaurant, true)
        toast.success(`Started a new cart with "${item.name}"`)
      }
    } else {
      toast.success(`Added "${item.name}" to cart 🛒`)
    }
  }

  if (loading) return <Loader label="Loading menu…" fullscreen />
  if (error) return <div className="mx-auto max-w-3xl px-4 py-12"><EmptyState emoji="⚠️" title="Oops" message={error} actionLabel="Back to restaurants" actionTo="/restaurants" /></div>

  const name = restaurant?.name || 'Restaurant'
  const rating = restaurant?.rating ?? fauxRating(name)

  return (
    <div className="pb-28">
      {/* Banner header */}
      <div className={`relative h-44 w-full overflow-hidden bg-gradient-to-br ${gradientFor(name)} sm:h-56`}>
        {restaurant?.image && (
          <img src={restaurant.image} alt={name} className="h-full w-full object-cover" />
        )}
        <motion.div
          className="absolute right-6 top-1/2 -translate-y-1/2 text-7xl opacity-80 sm:text-8xl"
          animate={{ y: [0, -10, 0] }}
          transition={{ repeat: Infinity, duration: 4, ease: 'easeInOut' }}
        >
          {emojiFor(name)}
        </motion.div>
        <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/30 to-transparent p-4 sm:p-6">
          <h1 className="font-display text-2xl font-extrabold text-white drop-shadow sm:text-4xl">{name}</h1>
          <div className="mt-2 flex flex-wrap items-center gap-2 text-sm text-white/95">
            <span className="badge-success bg-white/90"><Star className="h-3 w-3 fill-green-600 text-green-600" />{Number(rating).toFixed(1)}</span>
            <span className="badge bg-white/90 text-gray-700"><Clock className="h-3 w-3" />{deliveryTime(name)}</span>
            {restaurant?.city && <span className="badge bg-white/90 text-gray-700"><MapPin className="h-3 w-3" />{restaurant.city}</span>}
          </div>
        </div>
      </div>

      <div className="mx-auto max-w-4xl px-4">
        {restaurant?.description && (
          <p className="mt-4 text-gray-500">{restaurant.description}</p>
        )}

        {/* Sticky category tabs */}
        {groups.length > 1 && (
          <div className="sticky top-[65px] z-20 -mx-4 mt-4 flex gap-2 overflow-x-auto border-b border-gray-100 bg-[#fafaf9]/90 px-4 py-3 backdrop-blur">
            {groups.map((g) => (
              <a
                key={g.id}
                href={`#cat-${g.id}`}
                onClick={() => setActiveCat(g.id)}
                className={`chip whitespace-nowrap ${activeCat === g.id ? 'chip-active' : ''}`}
              >
                {g.name}
              </a>
            ))}
          </div>
        )}

        {/* Menu groups */}
        {items.length === 0 ? (
          <div className="py-8"><EmptyState emoji="📋" title="No menu yet" message="This kitchen hasn't added any dishes." /></div>
        ) : (
          <div className="mt-6 space-y-8">
            {groups.map((g) => (
              <section key={g.id} id={`cat-${g.id}`} className="scroll-mt-32">
                <h2 className="mb-3 font-display text-xl font-bold text-gray-900">{g.name}</h2>
                <div className="grid gap-3">
                  {g.items.map((item, i) => (
                    <MenuItemCard key={readId(item) ?? i} item={item} index={i} onAdd={handleAdd} />
                  ))}
                </div>
              </section>
            ))}
          </div>
        )}
      </div>

      {/* Sticky view-cart bar */}
      <AnimatePresence>
        {count > 0 && (
          <motion.div
            initial={{ y: 80, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: 80, opacity: 0 }}
            transition={{ type: 'spring', stiffness: 300, damping: 28 }}
            className="fixed inset-x-0 bottom-0 z-30 px-4 pb-4"
          >
            <Link
              to="/cart"
              className="mx-auto flex max-w-2xl items-center justify-between rounded-2xl bg-gradient-to-br from-brand-500 to-brand-600 px-5 py-3.5 text-white shadow-lift transition hover:to-brand-700"
            >
              <span className="flex items-center gap-2 font-semibold">
                <ShoppingCart className="h-5 w-5" />
                {count} item{count > 1 ? 's' : ''} · {rupees(subtotal)}
              </span>
              <span className="font-semibold">View cart →</span>
            </Link>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
