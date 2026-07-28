import { motion } from 'framer-motion'
import { Link } from 'react-router-dom'

// Friendly empty placeholder: big emoji/icon, message, optional CTA.
export default function EmptyState({
  emoji = '🍽️',
  title = 'Nothing here yet',
  message,
  actionLabel,
  actionTo,
  onAction,
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="card flex flex-col items-center px-6 py-16 text-center"
    >
      <motion.div
        className="text-6xl"
        animate={{ y: [0, -8, 0] }}
        transition={{ repeat: Infinity, duration: 3.5, ease: 'easeInOut' }}
      >
        {emoji}
      </motion.div>
      <h3 className="mt-4 text-lg font-semibold text-gray-900">{title}</h3>
      {message && <p className="mt-1 max-w-sm text-sm text-gray-500">{message}</p>}
      {actionLabel && actionTo && (
        <Link to={actionTo} className="btn-primary mt-6">
          {actionLabel}
        </Link>
      )}
      {actionLabel && onAction && !actionTo && (
        <button onClick={onAction} className="btn-primary mt-6">
          {actionLabel}
        </button>
      )}
    </motion.div>
  )
}
