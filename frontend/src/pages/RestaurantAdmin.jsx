import { useEffect, useState, useCallback } from 'react'
import { motion } from 'framer-motion'
import toast from 'react-hot-toast'
import { Store, Plus, Tag, UtensilsCrossed } from 'lucide-react'
import { restaurantsApi } from '../api/restaurants'
import { menuApi } from '../api/menu'
import Button from '../components/Button'
import Loader from '../components/Loader'
import EmptyState from '../components/EmptyState'
import { rupees, readId, readList, emojiFor, gradientFor } from '../lib/format'

// Restaurant-admin console: create a restaurant, add categories + menu items,
// and view the current menu for the selected restaurant.
export default function RestaurantAdmin() {
  const [restaurants, setRestaurants] = useState([])
  const [loading, setLoading] = useState(true)
  const [selectedId, setSelectedId] = useState('')

  const [menu, setMenu] = useState({ categories: [], items: [] })
  const [menuLoading, setMenuLoading] = useState(false)

  const [resForm, setResForm] = useState({ name: '', description: '', address: '', city: '' })
  const [catName, setCatName] = useState('')
  const [itemForm, setItemForm] = useState({ category_id: '', name: '', price: '', description: '', available: true })

  const [creatingRes, setCreatingRes] = useState(false)
  const [addingCat, setAddingCat] = useState(false)
  const [addingItem, setAddingItem] = useState(false)

  const loadRestaurants = useCallback(async () => {
    try {
      const data = await restaurantsApi.list()
      const list = readList(data)
      setRestaurants(list)
      setSelectedId((cur) => cur || (list[0] ? String(readId(list[0])) : ''))
    } catch { /* noop */ }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadRestaurants() }, [loadRestaurants])

  // Load the menu whenever the selected restaurant changes.
  const loadMenu = useCallback(async (rid) => {
    if (!rid) return
    setMenuLoading(true)
    try {
      const m = await menuApi.forRestaurant(rid)
      setMenu({ categories: m.categories || [], items: m.items || (Array.isArray(m) ? m : []) })
    } catch {
      setMenu({ categories: [], items: [] })
    } finally {
      setMenuLoading(false)
    }
  }, [])

  useEffect(() => { if (selectedId) loadMenu(selectedId) }, [selectedId, loadMenu])

  const createRestaurant = async (e) => {
    e.preventDefault()
    setCreatingRes(true)
    try {
      const created = await restaurantsApi.create(resForm)
      toast.success(`Created "${created.name || resForm.name}"`)
      setResForm({ name: '', description: '', address: '', city: '' })
      await loadRestaurants()
      const id = readId(created)
      if (id) setSelectedId(String(id))
    } catch {
      toast.error('Could not create restaurant.')
    } finally {
      setCreatingRes(false)
    }
  }

  const addCategory = async (e) => {
    e.preventDefault()
    if (!selectedId) return toast.error('Pick a restaurant first.')
    if (!catName.trim()) return
    setAddingCat(true)
    try {
      await menuApi.addCategory(selectedId, { name: catName.trim() })
      toast.success(`Added category "${catName}"`)
      setCatName('')
      await loadMenu(selectedId)
    } catch {
      toast.error('Could not add category.')
    } finally {
      setAddingCat(false)
    }
  }

  const addMenuItem = async (e) => {
    e.preventDefault()
    if (!selectedId) return toast.error('Pick a restaurant first.')
    setAddingItem(true)
    try {
      await menuApi.addItem(selectedId, {
        category_id: itemForm.category_id || (menu.categories[0] && readId(menu.categories[0])) || null,
        name: itemForm.name,
        description: itemForm.description,
        price: Number(itemForm.price),
        available: itemForm.available,
      })
      toast.success(`Added "${itemForm.name}"`)
      setItemForm({ category_id: '', name: '', price: '', description: '', available: true })
      await loadMenu(selectedId)
    } catch {
      toast.error('Could not add menu item.')
    } finally {
      setAddingItem(false)
    }
  }

  if (loading) return <Loader label="Loading console…" fullscreen />

  const selected = restaurants.find((r) => String(readId(r)) === String(selectedId))

  return (
    <div className="mx-auto max-w-5xl px-4 py-8">
      <h1 className="mb-1 font-display text-3xl font-bold text-gray-900">Restaurant console</h1>
      <p className="mb-6 text-gray-500">Manage your kitchens and menus.</p>

      {/* Restaurant selector */}
      {restaurants.length > 0 && (
        <div className="mb-6 flex flex-wrap items-center gap-2">
          <span className="text-sm font-medium text-gray-600">Active:</span>
          {restaurants.map((r) => (
            <button
              key={readId(r)}
              onClick={() => setSelectedId(String(readId(r)))}
              className={`chip ${String(readId(r)) === String(selectedId) ? 'chip-active' : ''}`}
            >
              <Store className="h-3.5 w-3.5" /> {r.name}
            </button>
          ))}
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-2">
        {/* Create restaurant */}
        <form onSubmit={createRestaurant} className="card space-y-3 p-5">
          <h2 className="flex items-center gap-2 font-display font-semibold text-gray-800"><Store className="h-4 w-4 text-brand-500" /> Create restaurant</h2>
          <input className="input" placeholder="Name" required value={resForm.name} onChange={(e) => setResForm((f) => ({ ...f, name: e.target.value }))} />
          <input className="input" placeholder="City" value={resForm.city} onChange={(e) => setResForm((f) => ({ ...f, city: e.target.value }))} />
          <input className="input" placeholder="Address" value={resForm.address} onChange={(e) => setResForm((f) => ({ ...f, address: e.target.value }))} />
          <textarea className="input" rows={2} placeholder="Description" value={resForm.description} onChange={(e) => setResForm((f) => ({ ...f, description: e.target.value }))} />
          <Button type="submit" loading={creatingRes} className="w-full">{creatingRes ? 'Creating…' : 'Create restaurant'}</Button>
        </form>

        {/* Add category + item */}
        <div className="space-y-6">
          <form onSubmit={addCategory} className="card space-y-3 p-5">
            <h2 className="flex items-center gap-2 font-display font-semibold text-gray-800"><Tag className="h-4 w-4 text-brand-500" /> Add category</h2>
            <input className="input" placeholder="e.g. Starters, Mains, Desserts" value={catName} onChange={(e) => setCatName(e.target.value)} />
            <Button type="submit" variant="secondary" loading={addingCat} className="w-full" disabled={!selectedId}>Add category</Button>
          </form>

          <form onSubmit={addMenuItem} className="card space-y-3 p-5">
            <h2 className="flex items-center gap-2 font-display font-semibold text-gray-800"><Plus className="h-4 w-4 text-brand-500" /> Add menu item</h2>
            <select className="input" value={itemForm.category_id} onChange={(e) => setItemForm((f) => ({ ...f, category_id: e.target.value }))}>
              <option value="">{menu.categories.length ? 'Select category…' : 'No categories yet'}</option>
              {menu.categories.map((c) => (
                <option key={readId(c)} value={readId(c)}>{c.name}</option>
              ))}
            </select>
            <input className="input" placeholder="Item name" required value={itemForm.name} onChange={(e) => setItemForm((f) => ({ ...f, name: e.target.value }))} />
            <input className="input" type="number" step="1" min="0" placeholder="Price (₹)" required value={itemForm.price} onChange={(e) => setItemForm((f) => ({ ...f, price: e.target.value }))} />
            <textarea className="input" rows={2} placeholder="Description" value={itemForm.description} onChange={(e) => setItemForm((f) => ({ ...f, description: e.target.value }))} />
            <label className="flex items-center gap-2 text-sm text-gray-600">
              <input type="checkbox" checked={itemForm.available} onChange={(e) => setItemForm((f) => ({ ...f, available: e.target.checked }))} /> Available
            </label>
            <Button type="submit" loading={addingItem} className="w-full" disabled={!selectedId}>{addingItem ? 'Adding…' : 'Add item'}</Button>
          </form>
        </div>
      </div>

      {/* Current menu */}
      <div className="mt-8">
        <h2 className="mb-3 flex items-center gap-2 font-display text-xl font-bold text-gray-900">
          <UtensilsCrossed className="h-5 w-5 text-brand-500" /> Current menu
          {selected && <span className="text-base font-normal text-gray-400">· {selected.name}</span>}
        </h2>
        {menuLoading ? (
          <Loader label="Loading menu…" />
        ) : menu.items.length === 0 ? (
          <EmptyState emoji="📋" title="No items yet" message="Add categories and dishes above to build your menu." />
        ) : (
          <div className="grid gap-3 sm:grid-cols-2">
            {menu.items.map((item, i) => {
              const cat = menu.categories.find((c) => readId(c) === (item.category_id ?? item.categoryId))
              return (
                <motion.div
                  key={readId(item) ?? i}
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: Math.min(i * 0.04, 0.3) }}
                  className="card flex items-center gap-3 p-4"
                >
                  <span className={`grid h-12 w-12 shrink-0 place-items-center rounded-xl bg-gradient-to-br ${gradientFor(item.name)} text-2xl`}>
                    {emojiFor(item.name)}
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <h4 className="truncate font-semibold text-gray-900">{item.name}</h4>
                      {item.available === false && <span className="badge-muted">Sold out</span>}
                    </div>
                    {cat && <p className="text-xs text-gray-400">{cat.name}</p>}
                    {item.description && <p className="line-clamp-1 text-sm text-gray-500">{item.description}</p>}
                  </div>
                  <span className="font-semibold text-gray-900">{rupees(item.price)}</span>
                </motion.div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
