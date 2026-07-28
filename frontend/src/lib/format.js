// Shared formatting + deterministic-imagery helpers.
// All food imagery is OFFLINE-SAFE: we derive a gradient + emoji from a string
// (restaurant/dish name) so the same entity always looks the same, with no
// dependency on an external image host.

// Indian rupee formatting. Accepts numbers or numeric strings.
export function rupees(value) {
  const n = Number(value)
  if (!Number.isFinite(n)) return '₹0'
  return '₹' + n.toLocaleString('en-IN', { maximumFractionDigits: 0, minimumFractionDigits: 0 })
}

// With paise (used where precision matters, e.g. line totals).
export function rupeesP(value) {
  const n = Number(value) || 0
  return '₹' + n.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

// Stable hash from a string -> non-negative integer.
function hash(str = '') {
  let h = 0
  for (let i = 0; i < str.length; i++) {
    h = (h << 5) - h + str.charCodeAt(i)
    h |= 0
  }
  return Math.abs(h)
}

// Warm gradient pairs that all sit nicely on a light theme.
const GRADIENTS = [
  'from-orange-200 via-amber-200 to-rose-200',
  'from-amber-200 via-orange-200 to-red-200',
  'from-rose-200 via-pink-200 to-orange-200',
  'from-lime-200 via-emerald-200 to-teal-200',
  'from-yellow-200 via-amber-200 to-orange-300',
  'from-sky-200 via-cyan-200 to-emerald-200',
  'from-violet-200 via-fuchsia-200 to-rose-200',
  'from-red-200 via-orange-200 to-amber-200',
]

const FOOD_EMOJI = ['🍕', '🍔', '🍜', '🍣', '🥘', '🌮', '🍛', '🍱', '🥗', '🍝', '🧆', '🍤', '🥙', '🍲', '🫔', '🥟']

// Pick a gradient class set for a name.
export function gradientFor(name = '') {
  return GRADIENTS[hash(name) % GRADIENTS.length]
}

// Pick a food emoji for a name (cuisine-aware nudges for common keywords).
export function emojiFor(name = '') {
  const n = name.toLowerCase()
  if (/pizza/.test(n)) return '🍕'
  if (/burger/.test(n)) return '🍔'
  if (/sushi|roll/.test(n)) return '🍣'
  if (/biryani|rice|curry/.test(n)) return '🍛'
  if (/noodle|ramen|chow/.test(n)) return '🍜'
  if (/taco|burrito/.test(n)) return '🌮'
  if (/salad/.test(n)) return '🥗'
  if (/pasta|spaghetti/.test(n)) return '🍝'
  if (/coffee|cafe|café/.test(n)) return '☕'
  if (/dessert|cake|sweet/.test(n)) return '🍰'
  return FOOD_EMOJI[hash(name) % FOOD_EMOJI.length]
}

// Deterministic faux rating in 3.8–4.9 range + delivery time 15–45 min.
export function fauxRating(name = '') {
  const r = 3.8 + (hash(name + 'r') % 12) / 10 // 3.8 .. 4.9
  return Math.min(4.9, Number(r.toFixed(1)))
}
export function deliveryTime(name = '') {
  const base = 15 + (hash(name + 'd') % 30) // 15 .. 44
  return `${base}-${base + 10} min`
}

// Read an id from id / _id / orderId defensively.
export function readId(obj) {
  return obj?.id ?? obj?._id ?? obj?.orderId ?? obj?.order_id
}

// Read an array from either a raw array or a { items } / { notifications } wrapper.
export function readList(data, key = 'items') {
  if (Array.isArray(data)) return data
  if (data && Array.isArray(data[key])) return data[key]
  if (data && Array.isArray(data.items)) return data.items
  return []
}

// Initials for an avatar (from name or email).
export function initials(user) {
  const src = user?.name || user?.email || '?'
  const parts = src.split(/[@\s._-]+/).filter(Boolean)
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase()
  return src.slice(0, 2).toUpperCase()
}
