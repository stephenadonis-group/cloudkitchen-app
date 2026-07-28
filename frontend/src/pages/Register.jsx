import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import toast from 'react-hot-toast'
import { Mail, Lock, User as UserIcon, ShoppingBag, ChefHat, Bike } from 'lucide-react'
import { useAuth } from '../store/AuthContext'
import Button from '../components/Button'
import AuthPanel from '../components/AuthPanel'
import { Field } from './Login'

const ROLES = [
  { value: 'customer', label: 'Customer', Icon: ShoppingBag, hint: 'Order food' },
  { value: 'restaurant-admin', label: 'Restaurant', Icon: ChefHat, hint: 'Sell food' },
  { value: 'delivery-agent', label: 'Delivery', Icon: Bike, hint: 'Deliver food' },
]

// Split-screen register with an animated role selector.
export default function Register() {
  const { register } = useAuth()
  const navigate = useNavigate()

  const [form, setForm] = useState({ name: '', email: '', password: '', role: 'customer' })
  const [submitting, setSubmitting] = useState(false)

  const update = (e) => setForm((f) => ({ ...f, [e.target.name]: e.target.value }))

  const submit = async (e) => {
    e.preventDefault()
    setSubmitting(true)
    try {
      const data = await register(form)
      toast.success('Account created! 🎉')
      // Route by role when auto-logged-in, else to login.
      if (data?.token) {
        navigate(form.role === 'restaurant-admin' ? '/admin/restaurant' : '/restaurants', { replace: true })
      } else {
        navigate('/login', { replace: true })
      }
    } catch (err) {
      toast.error(err?.response?.data?.message || 'Could not create account.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="mx-auto grid min-h-[calc(100vh-65px)] max-w-6xl items-stretch px-0 md:grid-cols-2">
      <AuthPanel
        title="Join the feast."
        subtitle="Create an account to order, cook, or deliver — CloudKitchen connects it all."
      />
      <div className="flex items-center justify-center px-4 py-12">
        <motion.div
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.4 }}
          className="card w-full max-w-md p-8"
        >
          <h1 className="text-2xl font-bold text-gray-900">Create your account</h1>
          <p className="mt-1 text-sm text-gray-500">Join CloudKitchen in seconds.</p>

          <form onSubmit={submit} className="mt-6 space-y-4">
            <Field icon={UserIcon} id="name" name="name" label="Full name" value={form.name} onChange={update} placeholder="Jane Doe" />
            <Field icon={Mail} id="email" name="email" type="email" label="Email" value={form.email} onChange={update} autoComplete="email" placeholder="you@example.com" />
            <Field icon={Lock} id="password" name="password" type="password" minLength={6} label="Password" value={form.password} onChange={update} autoComplete="new-password" placeholder="At least 6 characters" />

            <div>
              <label className="label">I want to</label>
              <div className="grid grid-cols-3 gap-2">
                {ROLES.map(({ value, label, Icon, hint }) => {
                  const active = form.role === value
                  return (
                    <motion.button
                      type="button"
                      key={value}
                      whileTap={{ scale: 0.95 }}
                      onClick={() => setForm((f) => ({ ...f, role: value }))}
                      className={`flex flex-col items-center gap-1 rounded-xl border-2 px-2 py-3 text-center transition ${
                        active
                          ? 'border-brand-500 bg-brand-50 text-brand-700 shadow-soft'
                          : 'border-gray-200 text-gray-500 hover:border-brand-200'
                      }`}
                    >
                      <Icon className="h-5 w-5" />
                      <span className="text-xs font-semibold">{label}</span>
                      <span className="text-[10px] text-gray-400">{hint}</span>
                    </motion.button>
                  )
                })}
              </div>
            </div>

            <Button type="submit" loading={submitting} className="w-full">
              {submitting ? 'Creating…' : 'Sign up'}
            </Button>
          </form>

          <p className="mt-6 text-center text-sm text-gray-500">
            Already have an account?{' '}
            <Link to="/login" className="font-semibold text-brand-600 hover:underline">Log in</Link>
          </p>
        </motion.div>
      </div>
    </div>
  )
}
