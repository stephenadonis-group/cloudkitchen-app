import {
  Clock,
  CheckCircle2,
  ChefHat,
  Bike,
  PackageCheck,
  XCircle,
  CreditCard,
  Loader2,
} from 'lucide-react'

// Maps order / payment / delivery statuses to a colour + icon + label.
// Tolerant of casing and minor naming differences from the backend.
const MAP = {
  // Order lifecycle
  PLACED: { cls: 'badge-info', Icon: Clock, label: 'Placed' },
  PENDING: { cls: 'badge-warning', Icon: Clock, label: 'Pending' },
  CONFIRMED: { cls: 'badge-info', Icon: CheckCircle2, label: 'Confirmed' },
  ACCEPTED: { cls: 'badge-info', Icon: CheckCircle2, label: 'Accepted' },
  PREPARING: { cls: 'badge-warning', Icon: ChefHat, label: 'Preparing' },
  READY: { cls: 'badge-warning', Icon: ChefHat, label: 'Ready' },
  ASSIGNED: { cls: 'badge-brand', Icon: Bike, label: 'Rider assigned' },
  OUT_FOR_DELIVERY: { cls: 'badge-brand', Icon: Bike, label: 'On the way' },
  DELIVERED: { cls: 'badge-success', Icon: PackageCheck, label: 'Delivered' },
  CANCELLED: { cls: 'badge-danger', Icon: XCircle, label: 'Cancelled' },
  // Payment
  SUCCESS: { cls: 'badge-success', Icon: CheckCircle2, label: 'Paid' },
  PAID: { cls: 'badge-success', Icon: CheckCircle2, label: 'Paid' },
  PROCESSING: { cls: 'badge-warning', Icon: Loader2, label: 'Processing' },
  FAILED: { cls: 'badge-danger', Icon: XCircle, label: 'Failed' },
}

export default function StatusBadge({ status, className = '' }) {
  const key = String(status || '').toUpperCase().replace(/\s+/g, '_')
  const cfg = MAP[key] || { cls: 'badge-muted', Icon: CreditCard, label: key || 'Unknown' }
  const { cls, Icon, label } = cfg
  return (
    <span className={`${cls} ${className}`}>
      <Icon className="h-3.5 w-3.5" />
      {label}
    </span>
  )
}
