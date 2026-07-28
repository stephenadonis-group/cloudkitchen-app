// Shimmer skeleton placeholders for loading states.

export function SkeletonBox({ className = '' }) {
  return <div className={`skeleton ${className}`} />
}

// Mimics a RestaurantCard while data loads.
export function CardSkeleton() {
  return (
    <div className="card overflow-hidden">
      <div className="skeleton h-32 w-full rounded-none" />
      <div className="space-y-3 p-4">
        <SkeletonBox className="h-4 w-2/3" />
        <SkeletonBox className="h-3 w-1/2" />
        <SkeletonBox className="h-3 w-1/3" />
      </div>
    </div>
  )
}

// Grid of card skeletons.
export function CardGridSkeleton({ count = 6 }) {
  return (
    <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
      {Array.from({ length: count }).map((_, i) => (
        <CardSkeleton key={i} />
      ))}
    </div>
  )
}

// Mimics a list row (orders, menu items).
export function ListSkeleton({ count = 4 }) {
  return (
    <div className="space-y-3">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="card flex items-center justify-between gap-4 p-4">
          <div className="flex-1 space-y-2">
            <SkeletonBox className="h-4 w-1/3" />
            <SkeletonBox className="h-3 w-1/2" />
          </div>
          <SkeletonBox className="h-9 w-20 rounded-xl" />
        </div>
      ))}
    </div>
  )
}
