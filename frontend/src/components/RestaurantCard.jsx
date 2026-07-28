import { Link } from 'react-router-dom'
import { motion } from 'framer-motion'
import { Star, Clock, MapPin } from 'lucide-react'
import {
  gradientFor,
  emojiFor,
  fauxRating,
  deliveryTime,
  readId,
} from '../lib/format'

// Restaurant tile for the listing grid.
// Imagery is an offline-safe gradient + emoji derived from the name (falls back
// to restaurant.image if the backend ever provides one).
export default function RestaurantCard({ restaurant, index = 0 }) {
  const id = readId(restaurant)
  const name = restaurant.name || 'Restaurant'
  const rating = restaurant.rating ?? restaurant.avgRating ?? fauxRating(name)
  const eta = deliveryTime(name)
  const subtitle = restaurant.cuisine || restaurant.description || 'Tasty food, delivered'
  const place = restaurant.city || restaurant.address || restaurant.location

  return (
    <motion.div
      initial={{ opacity: 0, y: 18 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, delay: Math.min(index * 0.05, 0.4), ease: [0.16, 1, 0.3, 1] }}
      whileHover={{ y: -6 }}
    >
      <Link
        to={`/restaurants/${id}`}
        className="card group block overflow-hidden transition-shadow duration-300 hover:shadow-lift"
      >
        <div className={`relative flex h-36 items-center justify-center bg-gradient-to-br ${gradientFor(name)}`}>
          {restaurant.image ? (
            <img src={restaurant.image} alt={name} className="h-full w-full object-cover" />
          ) : (
            <span className="text-5xl drop-shadow-sm transition-transform duration-300 group-hover:scale-110">
              {emojiFor(name)}
            </span>
          )}
          <span className="badge-brand absolute left-3 top-3 bg-white/90 backdrop-blur">
            <Clock className="h-3 w-3" /> {eta}
          </span>
        </div>
        <div className="p-4">
          <div className="flex items-start justify-between gap-2">
            <h3 className="truncate font-display font-semibold text-gray-900 group-hover:text-brand-600">
              {name}
            </h3>
            <span className="badge-success shrink-0">
              <Star className="h-3 w-3 fill-green-600 text-green-600" />
              {Number(rating).toFixed(1)}
            </span>
          </div>
          <p className="mt-1 line-clamp-1 text-sm text-gray-500">{subtitle}</p>
          {place && (
            <p className="mt-2 flex items-center gap-1 text-xs text-gray-400">
              <MapPin className="h-3 w-3" /> {place}
            </p>
          )}
        </div>
      </Link>
    </motion.div>
  )
}
