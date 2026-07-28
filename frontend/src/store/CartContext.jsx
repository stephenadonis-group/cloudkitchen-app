import { createContext, useContext, useEffect, useMemo, useState, useCallback } from 'react'

// Cart context: a local-first cart persisted in localStorage. Each line tracks
// the menu item plus quantity. A cart is scoped to a single restaurant — adding
// an item from a different restaurant prompts a reset.
const CartContext = createContext(null)

const CART_KEY = 'ck_cart'

function loadCart() {
  try {
    const raw = localStorage.getItem(CART_KEY)
    return raw ? JSON.parse(raw) : { restaurantId: null, restaurantName: null, items: [] }
  } catch {
    return { restaurantId: null, restaurantName: null, items: [] }
  }
}

export function CartProvider({ children }) {
  const [cart, setCart] = useState(loadCart)

  useEffect(() => {
    localStorage.setItem(CART_KEY, JSON.stringify(cart))
  }, [cart])

  // Add an item. Returns false if it belongs to a different restaurant and the
  // caller declined to reset (handled via the `force` flag from the UI).
  const addItem = useCallback((item, restaurant, force = false) => {
    let added = true
    setCart((prev) => {
      const rid = restaurant?.id ?? restaurant?._id
      if (prev.restaurantId && prev.restaurantId !== rid && prev.items.length > 0) {
        if (!force) {
          added = false
          return prev
        }
        // Different restaurant + forced: start a fresh cart.
        return {
          restaurantId: rid,
          restaurantName: restaurant?.name,
          items: [{ ...normalizeItem(item), quantity: 1 }],
        }
      }
      const itemId = item.id ?? item._id
      const existing = prev.items.find((i) => i.id === itemId)
      const items = existing
        ? prev.items.map((i) =>
            i.id === itemId ? { ...i, quantity: i.quantity + 1 } : i
          )
        : [...prev.items, { ...normalizeItem(item), quantity: 1 }]
      return {
        restaurantId: rid ?? prev.restaurantId,
        restaurantName: restaurant?.name ?? prev.restaurantName,
        items,
      }
    })
    return added
  }, [])

  const setQuantity = useCallback((itemId, quantity) => {
    setCart((prev) => {
      const items = prev.items
        .map((i) => (i.id === itemId ? { ...i, quantity } : i))
        .filter((i) => i.quantity > 0)
      return { ...prev, items, ...(items.length ? {} : { restaurantId: null, restaurantName: null }) }
    })
  }, [])

  const removeItem = useCallback((itemId) => {
    setCart((prev) => {
      const items = prev.items.filter((i) => i.id !== itemId)
      return items.length
        ? { ...prev, items }
        : { restaurantId: null, restaurantName: null, items: [] }
    })
  }, [])

  const clear = useCallback(() => {
    setCart({ restaurantId: null, restaurantName: null, items: [] })
  }, [])

  const totals = useMemo(() => {
    const subtotal = cart.items.reduce((sum, i) => sum + i.price * i.quantity, 0)
    const count = cart.items.reduce((sum, i) => sum + i.quantity, 0)
    return { subtotal, count }
  }, [cart.items])

  const value = { cart, addItem, setQuantity, removeItem, clear, ...totals }
  return <CartContext.Provider value={value}>{children}</CartContext.Provider>
}

function normalizeItem(item) {
  return {
    id: item.id ?? item._id,
    name: item.name,
    price: Number(item.price) || 0,
  }
}

export function useCart() {
  const ctx = useContext(CartContext)
  if (!ctx) throw new Error('useCart must be used within a CartProvider')
  return ctx
}
