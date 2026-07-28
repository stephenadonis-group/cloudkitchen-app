import { useState } from 'react'
import { Link, useNavigate, useLocation } from 'react-router-dom'
import { motion } from 'framer-motion'
import toast from 'react-hot-toast'
import { Mail, Lock } from 'lucide-react'
import { useAuth } from '../store/AuthContext'
import Button from '../components/Button'
import AuthPanel from '../components/AuthPanel'

// Split-screen login: branded gradient panel (left) + form card (right).
export default function Login() {
  const { login } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const from = location.state?.from?.pathname || '/restaurants'

  const [form, setForm] = useState({ email: '', password: '' })
  const [submitting, setSubmitting] = useState(false)

  const update = (e) => setForm((f) => ({ ...f, [e.target.name]: e.target.value }))

  const submit = async (e) => {
    e.preventDefault()
    setSubmitting(true)
    try {
      await login(form)
      toast.success('Welcome back! 🍴')
      navigate(from, { replace: true })
    } catch (err) {
      toast.error(err?.response?.data?.message || 'Invalid email or password.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="mx-auto grid min-h-[calc(100vh-65px)] max-w-6xl items-stretch gap-0 px-0 md:grid-cols-2">
      <AuthPanel
        title="Hungry? We've got you."
        subtitle="Log in to track orders, reorder favourites, and get food delivered hot and fast."
      />
      <div className="flex items-center justify-center px-4 py-12">
        <motion.div
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.4 }}
          className="card w-full max-w-md p-8"
        >
          <h1 className="text-2xl font-bold text-gray-900">Welcome back</h1>
          <p className="mt-1 text-sm text-gray-500">Log in to order from CloudKitchen.</p>

          <form onSubmit={submit} className="mt-6 space-y-4">
            <Field
              icon={Mail} id="email" name="email" type="email" label="Email"
              value={form.email} onChange={update} autoComplete="email" placeholder="you@example.com"
            />
            <Field
              icon={Lock} id="password" name="password" type="password" label="Password"
              value={form.password} onChange={update} autoComplete="current-password" placeholder="••••••••"
            />
            <Button type="submit" loading={submitting} className="w-full">
              {submitting ? 'Logging in…' : 'Log in'}
            </Button>
          </form>

          <p className="mt-6 text-center text-sm text-gray-500">
            No account?{' '}
            <Link to="/register" className="font-semibold text-brand-600 hover:underline">
              Create one
            </Link>
          </p>
        </motion.div>
      </div>
    </div>
  )
}

// Input with leading icon and focus animation. Exported pattern reused in Register.
export function Field({ icon: Icon, label, ...props }) {
  return (
    <div>
      <label className="label" htmlFor={props.id}>{label}</label>
      <div className="relative">
        {Icon && <Icon className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />}
        <input className={`input ${Icon ? 'pl-10' : ''}`} required {...props} />
      </div>
    </div>
  )
}
