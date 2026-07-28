import { useEffect, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import toast from 'react-hot-toast'
import { User, MapPin, Bell, Plus, Mail, Phone, Bike, CreditCard, Package, Megaphone } from 'lucide-react'
import { usersApi } from '../api/users'
import { notificationsApi } from '../api/orders'
import { useAuth } from '../store/AuthContext'
import Button from '../components/Button'
import Loader from '../components/Loader'
import EmptyState from '../components/EmptyState'
import { readList, initials } from '../lib/format'

// Tabbed profile: Details / Addresses / Notifications, with animated switching.
const TABS = [
  { key: 'details', label: 'Details', Icon: User },
  { key: 'addresses', label: 'Addresses', Icon: MapPin },
  { key: 'notifications', label: 'Notifications', Icon: Bell },
]

export default function Profile() {
  const { user, setUser } = useAuth()
  const [tab, setTab] = useState('details')
  const [profile, setProfile] = useState({ name: '', email: '', phone: '' })
  const [addresses, setAddresses] = useState([])
  const [notifications, setNotifications] = useState([])
  const [newAddress, setNewAddress] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    let active = true
    Promise.all([
      usersApi.getProfile().catch(() => user || {}),
      usersApi.getAddresses().catch(() => []),
      notificationsApi.list().catch(() => ({ notifications: [] })),
    ]).then(([p, a, n]) => {
      if (!active) return
      setProfile({ name: p?.name || user?.name || '', email: p?.email || user?.email || '', phone: p?.phone || '' })
      setAddresses(readList(a))
      setNotifications(readList(n, 'notifications'))
      setLoading(false)
    })
    return () => { active = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const saveProfile = async (e) => {
    e.preventDefault()
    setSaving(true)
    try {
      const updated = await usersApi.updateProfile(profile)
      setUser((u) => ({ ...u, ...(updated || profile) }))
      toast.success('Profile saved')
    } catch {
      toast.error('Could not save profile.')
    } finally {
      setSaving(false)
    }
  }

  const addAddress = async (e) => {
    e.preventDefault()
    if (!newAddress.trim()) return
    try {
      const created = await usersApi.addAddress({ line: newAddress.trim() })
      setAddresses((list) => [...list, created || { line: newAddress.trim() }])
      setNewAddress('')
      toast.success('Address added')
    } catch {
      toast.error('Could not add address.')
    }
  }

  if (loading) return <Loader label="Loading profile…" fullscreen />

  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      {/* Profile header */}
      <div className="mb-6 flex items-center gap-4">
        <div className="grid h-16 w-16 place-items-center rounded-2xl bg-gradient-to-br from-brand-500 to-brand-600 text-xl font-bold text-white shadow-lift">
          {initials(profile.name ? profile : user)}
        </div>
        <div>
          <h1 className="font-display text-2xl font-bold text-gray-900">{profile.name || 'Your profile'}</h1>
          <p className="text-sm text-gray-500">{profile.email}</p>
        </div>
      </div>

      {/* Tabs */}
      <div className="mb-5 flex gap-1 rounded-2xl bg-gray-100 p-1">
        {TABS.map(({ key, label, Icon }) => (
          <button
            key={key}
            onClick={() => setTab(key)}
            className={`relative flex flex-1 items-center justify-center gap-1.5 rounded-xl px-3 py-2 text-sm font-medium transition ${
              tab === key ? 'text-brand-700' : 'text-gray-500 hover:text-gray-700'
            }`}
          >
            {tab === key && (
              <motion.span layoutId="profile-tab" className="absolute inset-0 rounded-xl bg-white shadow-soft" />
            )}
            <span className="relative flex items-center gap-1.5"><Icon className="h-4 w-4" /> {label}</span>
          </button>
        ))}
      </div>

      <AnimatePresence mode="wait">
        <motion.div
          key={tab}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -8 }}
          transition={{ duration: 0.2 }}
        >
          {tab === 'details' && (
            <form onSubmit={saveProfile} className="card space-y-4 p-5">
              <div>
                <label className="label">Name</label>
                <div className="relative">
                  <User className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                  <input className="input pl-10" value={profile.name} onChange={(e) => setProfile((p) => ({ ...p, name: e.target.value }))} />
                </div>
              </div>
              <div>
                <label className="label">Email</label>
                <div className="relative">
                  <Mail className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                  <input className="input pl-10" type="email" value={profile.email} onChange={(e) => setProfile((p) => ({ ...p, email: e.target.value }))} />
                </div>
              </div>
              <div>
                <label className="label">Phone</label>
                <div className="relative">
                  <Phone className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                  <input className="input pl-10" value={profile.phone} onChange={(e) => setProfile((p) => ({ ...p, phone: e.target.value }))} />
                </div>
              </div>
              <Button type="submit" loading={saving}>{saving ? 'Saving…' : 'Save changes'}</Button>
            </form>
          )}

          {tab === 'addresses' && (
            <div className="card p-5">
              {addresses.length === 0 ? (
                <p className="mb-4 text-sm text-gray-500">No addresses saved yet.</p>
              ) : (
                <ul className="mb-4 space-y-2">
                  {addresses.map((a, i) => (
                    <li key={i} className="flex items-start gap-2 rounded-xl bg-gray-50 px-3 py-2.5 text-sm text-gray-700">
                      <MapPin className="mt-0.5 h-4 w-4 shrink-0 text-brand-500" />
                      {a.line || a.address || [a.line1, a.city, a.pincode].filter(Boolean).join(', ')}
                    </li>
                  ))}
                </ul>
              )}
              <form onSubmit={addAddress} className="flex gap-2">
                <input className="input" placeholder="Add a new address…" value={newAddress} onChange={(e) => setNewAddress(e.target.value)} />
                <Button type="submit" variant="secondary" className="shrink-0"><Plus className="h-4 w-4" /> Add</Button>
              </form>
            </div>
          )}

          {tab === 'notifications' && (
            notifications.length === 0 ? (
              <EmptyState emoji="🔔" title="No notifications" message="You're all caught up!" />
            ) : (
              <div className="space-y-2">
                {notifications.map((n, i) => (
                  <NotificationRow key={n.id ?? i} n={n} />
                ))}
              </div>
            )
          )}
        </motion.div>
      </AnimatePresence>
    </div>
  )
}

// Notification row: type icon + readable payload + timestamp.
function NotificationRow({ n }) {
  const type = String(n.type || '').toLowerCase()
  const Icon = /pay/.test(type) ? CreditCard
    : /deliver|assign|rider/.test(type) ? Bike
    : /order/.test(type) ? Package
    : Megaphone
  const when = n.sent_at || n.sentAt
  let text = n.message || n.text
  if (!text && n.payload) {
    text = typeof n.payload === 'string' ? n.payload : (n.payload.message || JSON.stringify(n.payload))
  }
  return (
    <motion.div
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      className="card flex items-start gap-3 p-4"
    >
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-xl bg-brand-50 text-brand-600">
        <Icon className="h-4 w-4" />
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium capitalize text-gray-800">{(n.type || 'Notification').replace(/_/g, ' ')}</p>
        {text && <p className="mt-0.5 break-words text-sm text-gray-500">{text}</p>}
        {n.channel && <span className="badge-muted mt-1.5">{n.channel}</span>}
      </div>
      {when && <span className="shrink-0 text-xs text-gray-400">{new Date(when).toLocaleDateString()}</span>}
    </motion.div>
  )
}
