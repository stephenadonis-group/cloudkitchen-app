import { motion } from 'framer-motion'

// Branded centered loader. Three bouncing dots + a spinning plate emoji feel
// more "food app" than a plain spinner.
export default function Loader({ label = 'Loading…', fullscreen = false }) {
  return (
    <div
      className={`flex flex-col items-center justify-center text-gray-500 ${
        fullscreen ? 'min-h-[60vh]' : 'py-20'
      }`}
    >
      <motion.div
        className="text-4xl"
        animate={{ rotate: 360 }}
        transition={{ repeat: Infinity, duration: 2.4, ease: 'linear' }}
      >
        🍽️
      </motion.div>
      <div className="mt-4 flex gap-1.5">
        {[0, 1, 2].map((i) => (
          <motion.span
            key={i}
            className="h-2 w-2 rounded-full bg-brand-500"
            animate={{ y: [0, -6, 0], opacity: [0.4, 1, 0.4] }}
            transition={{ repeat: Infinity, duration: 0.9, delay: i * 0.15 }}
          />
        ))}
      </div>
      {label && <p className="mt-3 text-sm font-medium">{label}</p>}
    </div>
  )
}

// Small inline spinner for buttons.
export function Spinner({ className = '' }) {
  return (
    <span
      className={`inline-block h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white ${className}`}
    />
  )
}
