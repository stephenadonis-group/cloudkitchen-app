# CloudKitchen — Frontend

React 18 + Vite + TailwindCSS SPA for the CloudKitchen food-delivery platform.
Talks to the backend microservices behind a single ingress.

## Stack

- **React 18** + **React Router v6**
- **Vite 5** (dev server + build)
- **TailwindCSS 3**
- **Axios** with a JWT interceptor

## Getting started

```bash
cp .env.example .env      # set VITE_API_BASE_URL for your backend
npm install
npm run dev               # http://localhost:5173
```

In dev, Vite proxies `/api/*` to `VITE_API_BASE_URL` (default
`http://localhost:8080`) so there are no CORS issues.

### Build

```bash
npm run build             # outputs to dist/
npm run preview           # preview the production build
```

## Configuration

| Var                 | Default                  | Description                                  |
| ------------------- | ------------------------ | -------------------------------------------- |
| `VITE_API_BASE_URL` | `/` (prod), `:8080` dev  | Base URL of the backend ingress / gateway.   |

In production the SPA is served behind the same ingress as the API, so the
default `/` makes all `/api/*` calls relative.

## Auth & roles

- JWT is stored in `localStorage` (`ck_token`) and attached as
  `Authorization: Bearer <token>` by the Axios request interceptor
  (`src/api/client.js`).
- A 401 response clears the token and redirects to `/login`.
- Roles: `customer`, `restaurant-admin`, `delivery-agent`, `admin`.
  `ProtectedRoute` enforces auth and (optionally) a role allowlist.

## Project structure

```
src/
  api/        # axios client + per-domain modules (auth, restaurants, menu, orders, users)
  store/      # AuthContext (useAuth) + CartContext (useCart), both localStorage-backed
  components/ # Navbar, ProtectedRoute, RestaurantCard, MenuItemCard, Loader
  pages/      # Login, Register, Restaurants, RestaurantMenu, Cart, Checkout,
              # Orders, OrderTrack, Profile, RestaurantAdmin, AdminDashboard
  App.jsx     # router
  main.jsx    # providers + bootstrap
```

## Key flows

- **Browse / search**: `/restaurants` lists kitchens; the search box hits
  `/api/menu/search?q=`.
- **Order**: add items (cart is scoped to one restaurant) → `/cart` → `/checkout`
  which creates the order (`POST /api/orders`) then runs a mock payment
  (`POST /api/payments/order/:id`) and routes to live tracking.
- **Track**: `/orders/:id` polls `/api/orders/:id/track` every 8s and shows a
  status timeline plus payment/delivery info.
- **Restaurant admin**: `/admin/restaurant` to create restaurants and add menu items.
- **Platform admin**: `/admin` dashboard placeholder.

## Docker

Multi-stage build (Node build → `nginx:alpine` static serve), non-root, SPA
fallback to `index.html`, exposes port 80.

```bash
docker build -t cloudkitchen-frontend .
# override the API base at build time if not served behind the same ingress:
# docker build --build-arg VITE_API_BASE_URL=https://api.example.com -t cloudkitchen-frontend .
docker run -p 8080:80 cloudkitchen-frontend
```
