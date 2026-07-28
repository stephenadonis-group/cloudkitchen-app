import clsx from 'clsx'
import { Spinner } from './Loader'

// Branded button wrapping the .btn-* design-system classes.
// variant: primary | secondary | ghost | danger
export default function Button({
  variant = 'primary',
  loading = false,
  disabled,
  className,
  children,
  ...props
}) {
  const variantClass = {
    primary: 'btn-primary',
    secondary: 'btn-secondary',
    ghost: 'btn-ghost',
    danger: 'btn-danger',
  }[variant]

  return (
    <button
      className={clsx(variantClass, className)}
      disabled={disabled || loading}
      {...props}
    >
      {loading && <Spinner />}
      {children}
    </button>
  )
}
