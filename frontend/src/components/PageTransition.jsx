import { motion } from 'framer-motion'

// Wraps each routed page so AnimatePresence in App.jsx can cross-fade/slide on
// navigation. Uses a gentle fade + upward slide.
export default function PageTransition({ children }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -8 }}
      transition={{ duration: 0.28, ease: [0.16, 1, 0.3, 1] }}
    >
      {children}
    </motion.div>
  )
}
