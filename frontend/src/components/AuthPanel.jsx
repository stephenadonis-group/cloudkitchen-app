import { motion } from 'framer-motion'

// Branded gradient panel for the login/register split-screen.
// Floating food emojis + tagline. Hidden on mobile (form takes the full width).
const EMOJIS = ['🍕', '🍔', '🍜', '🍣', '🌮', '🍛', '🥗', '🍩', '🍱', '🧋']

export default function AuthPanel({ title, subtitle }) {
  return (
    <div className="relative hidden overflow-hidden bg-gradient-to-br from-brand-500 via-brand-600 to-orange-700 md:block">
      {/* Floating emoji field */}
      {EMOJIS.map((e, i) => (
        <motion.span
          key={i}
          className="absolute text-3xl opacity-30 md:text-4xl"
          style={{ left: `${(i * 37) % 90 + 5}%`, top: `${(i * 53) % 85 + 5}%` }}
          animate={{ y: [0, -18, 0], rotate: [0, 8, -8, 0] }}
          transition={{ repeat: Infinity, duration: 5 + (i % 4), delay: i * 0.3, ease: 'easeInOut' }}
        >
          {e}
        </motion.span>
      ))}

      <div className="relative flex h-full flex-col justify-between p-10 text-white">
        <div className="flex items-center gap-2 text-xl font-extrabold">
          <span className="grid h-9 w-9 place-items-center rounded-xl bg-white/20 backdrop-blur">🍴</span>
          <span className="font-display">CloudKitchen</span>
        </div>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, delay: 0.1 }}
        >
          <h2 className="max-w-sm font-display text-4xl font-extrabold leading-tight text-balance">
            {title}
          </h2>
          <p className="mt-4 max-w-sm text-white/85">{subtitle}</p>
        </motion.div>

        <div className="flex gap-6 text-sm text-white/80">
          <div>
            <p className="font-display text-2xl font-bold text-white">500+</p>
            <p>Kitchens</p>
          </div>
          <div>
            <p className="font-display text-2xl font-bold text-white">30 min</p>
            <p>Avg delivery</p>
          </div>
          <div>
            <p className="font-display text-2xl font-bold text-white">4.8★</p>
            <p>Avg rating</p>
          </div>
        </div>
      </div>
    </div>
  )
}
