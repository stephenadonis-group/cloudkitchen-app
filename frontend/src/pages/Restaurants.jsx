import { useEffect, useMemo, useState } from 'react'
import { motion } from 'framer-motion'
import { Search, X } from 'lucide-react'
import { restaurantsApi } from '../api/restaurants'
import { menuApi } from '../api/menu'
import RestaurantCard from '../components/RestaurantCard'
import MenuItemCard from '../components/MenuItemCard'
import EmptyState from '../components/EmptyState'
import { CardGridSkeleton } from '../components/Skeleton'
import { readList } from '../lib/format'

// Restaurant discovery: hero + search bar that searches dishes (/api/menu/search)
// AND filters the loaded restaurant list by name/city. City filter chips too.
export default function Restaurants() {
  const [restaurants, setRestaurants] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const [query, setQuery] = useState('')
  const [dishResults, setDishResults] = useState(null) // null = not searching dishes
  const [searching, setSearching] = useState(false)
  const [cityFilter, setCityFilter] = useState('all')

  useEffect(() => {
    let active = true
    restaurantsApi
      .list()
      .then((data) => active && setRestaurants(readList(data)))
      .catch(() => active && setError('Could not load restaurants.'))
      .finally(() => active && setLoading(false))
    return () => { active = false }
  }, [])

  // Distinct cities for filter chips.
  const cities = useMemo(() => {
    const set = new Set(restaurants.map((r) => r.city).filter(Boolean))
    return ['all', ...set]
  }, [restaurants])

  // Client-side restaurant filtering by query text + city chip.
  const filteredRestaurants = useMemo(() => {
    const q = query.trim().toLowerCase()
    return restaurants.filter((r) => {
      const matchCity = cityFilter === 'all' || r.city === cityFilter
      const matchText =
        !q ||
        (r.name || '').toLowerCase().includes(q) ||
        (r.city || '').toLowerCase().includes(q) ||
        (r.description || '').toLowerCase().includes(q)
      return matchCity && matchText
    })
  }, [restaurants, query, cityFilter])

  const runDishSearch = async (e) => {
    e.preventDefault()
    const q = query.trim()
    if (!q) { setDishResults(null); return }
    setSearching(true)
    try {
      const data = await menuApi.search(q)
      setDishResults(readList(data))
    } catch {
      setDishResults([])
    } finally {
      setSearching(false)
    }
  }

  const clearSearch = () => { setQuery(''); setDishResults(null) }

  return (
    <div>
      {/* Hero */}
      <section className="relative overflow-hidden food-gradient">
        <div className="mx-auto max-w-6xl px-4 py-12 sm:py-16">
          <motion.h1
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            className="font-display text-3xl font-extrabold text-gray-900 sm:text-5xl text-balance"
          >
            Order food you'll <span className="text-brand-600">love</span>, delivered fast 🛵
          </motion.h1>
          <motion.p
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.08 }}
            className="mt-2 max-w-xl text-gray-700"
          >
            Discover the best kitchens near you. Search a dish or a restaurant.
          </motion.p>

          <motion.form
            onSubmit={runDishSearch}
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.16 }}
            className="mt-6 flex max-w-xl gap-2"
          >
            <div className="relative flex-1">
              <Search className="pointer-events-none absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-gray-400" />
              <input
                className="input h-12 rounded-2xl pl-12 pr-10 text-base shadow-card"
                placeholder="Search dishes or restaurants…"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
              {query && (
                <button type="button" onClick={clearSearch} className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600">
                  <X className="h-5 w-5" />
                </button>
              )}
            </div>
            <button type="submit" className="btn-primary h-12 px-6 rounded-2xl">Search</button>
          </motion.form>
        </div>
      </section>

      <div className="mx-auto max-w-6xl px-4 py-8">
        {/* City filter chips */}
        {cities.length > 1 && dishResults === null && (
          <div className="mb-6 flex flex-wrap gap-2">
            {cities.map((c) => (
              <button
                key={c}
                onClick={() => setCityFilter(c)}
                className={`chip ${cityFilter === c ? 'chip-active' : ''}`}
              >
                {c === 'all' ? 'All cities' : c}
              </button>
            ))}
          </div>
        )}

        {/* Dish search results take priority when present */}
        {dishResults !== null ? (
          searching ? (
            <CardGridSkeleton count={4} />
          ) : dishResults.length === 0 ? (
            <EmptyState emoji="🔍" title="No dishes found" message={`Nothing matched "${query}". Try another dish.`} actionLabel="Clear search" onAction={clearSearch} />
          ) : (
            <div>
              <h2 className="mb-4 font-display text-lg font-semibold text-gray-800">
                {dishResults.length} dish{dishResults.length === 1 ? '' : 'es'} found
              </h2>
              <div className="grid gap-3 sm:grid-cols-2">
                {dishResults.map((item, i) => (
                  <MenuItemCard key={item.id ?? item._id ?? i} item={item} index={i} onAdd={() => {}} />
                ))}
              </div>
              <p className="mt-4 text-sm text-gray-400">Open a restaurant to add dishes to your cart.</p>
            </div>
          )
        ) : loading ? (
          <CardGridSkeleton />
        ) : error ? (
          <EmptyState emoji="⚠️" title="Couldn't load" message={error} />
        ) : filteredRestaurants.length === 0 ? (
          <EmptyState emoji="🍽️" title="No restaurants" message="No kitchens match your filters yet." />
        ) : (
          <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {filteredRestaurants.map((r, i) => (
              <RestaurantCard key={r.id ?? r._id} restaurant={r} index={i} />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
