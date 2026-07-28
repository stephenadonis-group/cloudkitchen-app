# CloudKitchen — PostgreSQL Database Guide

This guide explains how to connect to the PostgreSQL database running
inside the GKE cluster and query every table belonging to the 8 Go
microservices.

It is the **post-deploy companion** to `docs/gcp/01-07` — once Phase 4
is green and pods are Ready, every command below works as-is.

---

## How the Database is Set Up

CloudKitchen runs **1 PostgreSQL pod** (`postgres-0`) as a StatefulSet
inside the `cloudkitchen` namespace. Unlike a "database-per-service"
layout, every microservice points at **one shared database called
`cloudkitchen`**. Isolation between services is done with **PostgreSQL
schemas** instead — each service writes its tables under its own
schema, and the Go services set `search_path` so they only "see" their
own schema by default.

| Service | Schema | Tables in that schema | What it stores |
|---|---|---|---|
| auth-service         | `auth`          | `users`                                | Login credentials + JWT identity (email, password hash, role) |
| user-service         | `users`         | `profiles`, `addresses`                | Editable user profile + saved delivery addresses |
| restaurant-service   | `restaurants`   | `restaurants`                          | Restaurant registry (name, city, status, owner) |
| menu-service         | `menu`          | `categories`, `menu_items`             | Restaurant menus (categories + priced items) |
| order-service        | `orders`        | `orders`, `order_items`                | Customer orders + line items |
| payment-service      | `payments`      | `payments`                             | Payment transactions tied to orders |
| delivery-service     | `delivery`      | `agents`, `deliveries`                 | Delivery agents (10 pre-seeded) + delivery state |
| notification-service | `notifications` | `notifications`                        | Outbound notifications (event-driven, JSON payload) |

**Total: 8 schemas, 12 tables, 1 database.**

> ⚠️ **Schema naming heads-up** — the schema called `auth` is owned by
> `auth-service`, but the schema called `users` (plural) is owned by
> `user-service`, NOT auth-service. So `auth.users` and `users.profiles`
> are owned by **different** services even though both names contain
> "user". The split is intentional: `auth-service` owns the credential
> identity, `user-service` owns the editable profile, linked by
> `user_id` foreign key.

> 💡 **A fresh cluster does NOT mean an empty DB** — the delivery
> migration **seeds 10 dispatch agents** on first startup (`Alice
> Rider`, `Bob Courier`, …, `Jack Jet`). Every other table starts at
> 0 rows.

---

## Step 1: Connect to the Cluster + the Postgres Pod

First, make sure your `kubectl` context is pointed at the GKE cluster
you just deployed:

```bash
gcloud container clusters get-credentials <CLUSTER_NAME> \
  --zone <ZONE> --project <PROJECT_ID>

# Sanity-check: pod should show Running 1/1
kubectl -n cloudkitchen get pod postgres-0
```

There are two ways to query — pick the one that fits the moment.

### Option A — Run a Single Query (Quick One-Liner)

Best for ad-hoc checks (count rows, verify a column, see the latest
row).

```bash
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen -c "<SQL query>"
```

**Example:**

```bash
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen -c "SELECT id, email, role FROM auth.users;"
```

### Option B — Open an Interactive `psql` Shell (Exploration)

Best when you want to look around — switch schemas, describe tables,
run a few queries in a row.

```bash
kubectl exec -it -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen
```

You'll see the `cloudkitchen=#` prompt. The most useful commands inside:

```sql
-- ── Discover layout ──
\dn                          -- list ALL schemas (you should see 8: auth, users,
                             --   restaurants, menu, orders, payments, delivery,
                             --   notifications)

\dt *.*                      -- list tables in EVERY schema (not just public)

-- ── Switch schema (so you can drop the prefix) ──
SET search_path TO auth;     -- now `SELECT * FROM users` means `auth.users`
SHOW search_path;            -- confirm what's active

-- ── Describe a table ──
\d auth.users                -- columns + indexes + constraints
\d+ orders.orders            -- + storage stats

-- ── Run any SQL ──
SELECT * FROM auth.users LIMIT 5;
SELECT count(*) FROM orders.orders;

-- ── Exit ──
\q
```

> 💡 **Why `\dt *.*` and not `\dt`** — by default `\dt` only lists
> tables in the schemas listed in your `search_path` (which defaults to
> `"$user", public`). Since CloudKitchen puts every table in a custom
> schema, plain `\dt` returns **0 rows** on a fresh shell. Use
> `\dt *.*` to see them all, or `SET search_path TO <schema>;` first.

---

## Step 2: Query Each Schema

Each sub-section below uses the **fully-qualified `schema.table`** form
so the queries work from a fresh shell without `SET search_path`.

---

### Schema 1: `auth` — Login Credentials

Owned by **auth-service**. Stores the credential identity (what
`/api/auth/login` and `/api/auth/signup` write to).

**Table: `auth.users`**

| Column        | Type        | Description |
|---------------|-------------|-------------|
| `id`            | UUID        | Unique user ID — referenced by `users.profiles`, `users.addresses` |
| `email`         | TEXT        | Email, unique (login key) |
| `password_hash` | TEXT        | bcrypt hash (never raw password) |
| `role`          | TEXT        | `customer` / `owner` / `admin` |
| `created_at`    | TIMESTAMPTZ | Signup time |

```bash
# Every registered account
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, email, role, created_at FROM auth.users ORDER BY created_at DESC;"

# Count total accounts
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT COUNT(*) AS total_users FROM auth.users;"

# Find one user by email
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, email, role FROM auth.users WHERE email = 'vijay@example.com';"

# Signups today
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, email, created_at FROM auth.users WHERE created_at::date = CURRENT_DATE;"

# Accounts grouped by role
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT role, COUNT(*) FROM auth.users GROUP BY role;"
```

---

### Schema 2: `users` — Editable Profiles + Addresses

Owned by **user-service**. The "human" half of a user (vs. the
credential half in `auth.users`).

**Table: `users.profiles`**

| Column      | Type | Description |
|-------------|------|-------------|
| `user_id`     | UUID | PK — same value as `auth.users.id` (cross-service join key) |
| `full_name`   | TEXT | Display name (empty until user fills profile) |
| `phone`      | TEXT | Phone number (empty until user fills profile) |

**Table: `users.addresses`**

| Column      | Type    | Description |
|-------------|---------|-------------|
| `id`          | UUID    | Address ID |
| `user_id`     | UUID    | Owner — references `auth.users.id` |
| `line1`       | TEXT    | Street / building line |
| `city`        | TEXT    | City |
| `pincode`     | TEXT    | Postal / ZIP code |
| `is_default`  | BOOLEAN | True for the user's primary delivery address |

```bash
# All profiles
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT * FROM users.profiles;"

# Join profile + email from auth.users (cross-schema join)
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT a.email, p.full_name, p.phone FROM auth.users a JOIN users.profiles p ON p.user_id = a.id;"

# All saved addresses
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, user_id, line1, city, pincode, is_default FROM users.addresses ORDER BY user_id;"

# Default addresses only
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT user_id, line1, city, pincode FROM users.addresses WHERE is_default = true;"

# Cities our customers are spread across
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT city, COUNT(*) FROM users.addresses GROUP BY city ORDER BY 2 DESC;"
```

---

### Schema 3: `restaurants` — Restaurant Registry

Owned by **restaurant-service**.

**Table: `restaurants.restaurants`**

| Column        | Type        | Description |
|---------------|-------------|-------------|
| `id`            | UUID        | Restaurant ID |
| `owner_id`      | UUID        | The `auth.users.id` of the restaurant owner |
| `name`          | TEXT        | Display name |
| `description`   | TEXT        | Free-text description |
| `address`       | TEXT        | Street address |
| `city`          | TEXT        | City |
| `status`        | TEXT        | `active` / `inactive` |
| `created_at`    | TIMESTAMPTZ | When registered |

```bash
# Every restaurant
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, name, city, status, created_at FROM restaurants.restaurants ORDER BY created_at DESC;"

# Active restaurants only
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, name, city FROM restaurants.restaurants WHERE status = 'active';"

# Restaurants per city
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT city, COUNT(*) FROM restaurants.restaurants GROUP BY city ORDER BY 2 DESC;"

# Restaurants owned by a specific user (replace OWNER_UUID)
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, name, city FROM restaurants.restaurants WHERE owner_id = 'OWNER_UUID';"
```

---

### Schema 4: `menu` — Categories + Menu Items

Owned by **menu-service**. Two tables linked by `category_id`.

**Table: `menu.categories`**

| Column          | Type | Description |
|-----------------|------|-------------|
| `id`              | UUID | Category ID |
| `restaurant_id`   | UUID | Restaurant this category belongs to |
| `name`            | TEXT | "Starters", "Mains", "Drinks", … |

**Table: `menu.menu_items`**

| Column         | Type           | Description |
|----------------|----------------|-------------|
| `id`             | UUID           | Item ID |
| `restaurant_id`  | UUID           | Restaurant |
| `category_id`    | UUID           | Parent category (FK to `menu.categories.id`) |
| `name`           | TEXT           | Item name (e.g., "Margherita Pizza") |
| `description`    | TEXT           | Item description |
| `price`          | NUMERIC(10,2)  | Price |
| `available`      | BOOLEAN        | `true` = sellable, `false` = hidden |

```bash
# All categories
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, restaurant_id, name FROM menu.categories ORDER BY restaurant_id;"

# All menu items, joined with category + restaurant name
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "
  SELECT r.name AS restaurant, c.name AS category, mi.name AS item, mi.price, mi.available
  FROM menu.menu_items mi
  JOIN menu.categories c ON c.id = mi.category_id
  JOIN restaurants.restaurants r ON r.id = mi.restaurant_id
  ORDER BY r.name, c.name, mi.name;"

# Just the items, no joins
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT name, price, available FROM menu.menu_items ORDER BY price DESC LIMIT 20;"

# Out-of-stock items
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT name, price FROM menu.menu_items WHERE available = false;"

# Average price per restaurant
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "
  SELECT r.name AS restaurant, ROUND(AVG(mi.price), 2) AS avg_price, COUNT(mi.id) AS items
  FROM menu.menu_items mi
  JOIN restaurants.restaurants r ON r.id = mi.restaurant_id
  GROUP BY r.name ORDER BY avg_price DESC;"
```

---

### Schema 5: `orders` — Orders + Line Items

Owned by **order-service**. Two tables — `orders.orders` is the
"header", `orders.order_items` is one row per item in the cart.

**Table: `orders.orders`**

| Column          | Type           | Description |
|-----------------|----------------|-------------|
| `id`              | UUID           | Order ID |
| `customer_id`     | TEXT           | `auth.users.id` of the buyer (stored as text, not UUID) |
| `restaurant_id`   | TEXT           | Restaurant the order is from |
| `status`          | TEXT           | `PENDING` / `PAID` / `OUT_FOR_DELIVERY` / `DELIVERED` / `CANCELLED` |
| `total`           | NUMERIC(12,2)  | Order total |
| `created_at`      | TIMESTAMPTZ    | When placed |

**Table: `orders.order_items`**

| Column     | Type           | Description |
|------------|----------------|-------------|
| `id`         | UUID           | Item row ID |
| `order_id`   | UUID           | Parent order (FK to `orders.orders.id`, `ON DELETE CASCADE`) |
| `item_id`    | TEXT           | Menu item ID |
| `name`       | TEXT           | Snapshot of item name at order time (in case menu changes later) |
| `qty`        | INT            | Quantity ordered |
| `price`      | NUMERIC(12,2)  | Snapshot of price at order time |

```bash
# Every order
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, customer_id, restaurant_id, status, total, created_at
      FROM orders.orders ORDER BY created_at DESC;"

# Count orders by status
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT status, COUNT(*) AS count, SUM(total) AS revenue
      FROM orders.orders GROUP BY status ORDER BY count DESC;"

# Orders placed today
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, customer_id, status, total
      FROM orders.orders WHERE created_at::date = CURRENT_DATE;"

# Drill into one order's line items (replace ORDER_UUID)
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT name, qty, price, (qty * price) AS line_total
      FROM orders.order_items WHERE order_id = 'ORDER_UUID';"

# Top-selling items by quantity (across all orders)
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT name, SUM(qty) AS units_sold, SUM(qty * price) AS revenue
      FROM orders.order_items GROUP BY name ORDER BY units_sold DESC LIMIT 10;"

# Top customers by spend
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT customer_id, COUNT(*) AS orders_placed, SUM(total) AS lifetime_spend
      FROM orders.orders GROUP BY customer_id ORDER BY lifetime_spend DESC LIMIT 10;"

# Revenue per restaurant
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT restaurant_id, COUNT(*) AS orders, SUM(total) AS revenue
      FROM orders.orders WHERE status IN ('PAID','OUT_FOR_DELIVERY','DELIVERED')
      GROUP BY restaurant_id ORDER BY revenue DESC;"
```

---

### Schema 6: `payments` — Payment Transactions

Owned by **payment-service**. One row per payment attempt.

**Table: `payments.payments`**

| Column        | Type           | Description |
|---------------|----------------|-------------|
| `id`            | UUID           | Payment ID |
| `order_id`      | TEXT           | Which order this paid for (FK by convention) |
| `amount`        | NUMERIC(12,2)  | Amount charged |
| `method`        | TEXT           | `CARD` (default), `UPI`, `COD`, … |
| `status`        | TEXT           | `SUCCESS` / `FAILED` / `PENDING` / `REFUNDED` |
| `created_at`    | TIMESTAMPTZ    | When the attempt happened |

```bash
# All payments
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, order_id, amount, method, status, created_at
      FROM payments.payments ORDER BY created_at DESC;"

# Successful payments only
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, order_id, amount, method
      FROM payments.payments WHERE status = 'SUCCESS' ORDER BY created_at DESC;"

# Failed payments (debugging)
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, order_id, amount, method, created_at
      FROM payments.payments WHERE status = 'FAILED';"

# Money collected (only SUCCESS rows count)
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT COUNT(*) AS txns, SUM(amount) AS total_collected
      FROM payments.payments WHERE status = 'SUCCESS';"

# Payment-method mix
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT method, COUNT(*), SUM(amount) FROM payments.payments
      WHERE status = 'SUCCESS' GROUP BY method ORDER BY 2 DESC;"

# Payment(s) for one specific order (replace ORDER_UUID)
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, amount, method, status, created_at
      FROM payments.payments WHERE order_id = 'ORDER_UUID';"
```

---

### Schema 7: `delivery` — Agents + Deliveries

Owned by **delivery-service**.

**Table: `delivery.agents`**

| Column       | Type    | Description |
|--------------|---------|-------------|
| `id`           | UUID    | Agent ID |
| `name`         | TEXT    | Agent's display name |
| `phone`        | TEXT    | Phone number |
| `available`    | BOOLEAN | `true` = idle and assignable, `false` = currently on a delivery |

> 💡 **Pre-seeded data** — `delivery.agents` is **populated with 10
> agents at first startup** (Alice Rider, Bob Courier, …, Jack Jet). So
> this table is never empty, even on a brand-new cluster.

**Table: `delivery.deliveries`**

| Column        | Type        | Description |
|---------------|-------------|-------------|
| `id`            | UUID        | Delivery ID |
| `order_id`      | TEXT        | Which order is being delivered |
| `agent_id`      | UUID        | Assigned agent (FK to `delivery.agents.id`) |
| `status`        | TEXT        | `ASSIGNED` / `PICKED_UP` / `DELIVERED` / `FAILED` |
| `created_at`    | TIMESTAMPTZ | When the delivery was created |
| `updated_at`    | TIMESTAMPTZ | Last status update |

> ⚠️ **Deliveries don't auto-simulate** — placing an order via the React
> UI creates an `ASSIGNED` row, but moving it to `PICKED_UP` →
> `DELIVERED` requires a manual API call (the demo's driver app is the
> human running the smoke test). So you'll typically see most
> `delivery.deliveries` rows stuck at `ASSIGNED` unless you manually
> advance them.

```bash
# All 10 agents + their availability
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT name, phone, available FROM delivery.agents ORDER BY name;"

# Currently idle agents (can take a new order)
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT name, phone FROM delivery.agents WHERE available = true;"

# All deliveries
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, order_id, agent_id, status, created_at, updated_at
      FROM delivery.deliveries ORDER BY created_at DESC;"

# Deliveries with agent name (join)
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT d.order_id, a.name AS agent, d.status, d.updated_at
      FROM delivery.deliveries d
      LEFT JOIN delivery.agents a ON a.id = d.agent_id
      ORDER BY d.created_at DESC;"

# Status breakdown
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT status, COUNT(*) FROM delivery.deliveries GROUP BY status;"

# Agent workload (who delivered the most)
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT a.name, COUNT(d.id) AS deliveries_done
      FROM delivery.agents a
      LEFT JOIN delivery.deliveries d ON d.agent_id = a.id AND d.status = 'DELIVERED'
      GROUP BY a.name ORDER BY deliveries_done DESC;"
```

---

### Schema 8: `notifications` — Outbound Notifications

Owned by **notification-service**. Consumes events from NATS JetStream
and writes one row per dispatched notification.

**Table: `notifications.notifications`**

| Column     | Type        | Description |
|------------|-------------|-------------|
| `id`         | UUID        | Notification ID |
| `user_id`    | TEXT        | Recipient — `auth.users.id` |
| `channel`    | TEXT        | `EMAIL` / `SMS` / `PUSH` (demo logs them; no real send) |
| `type`       | TEXT        | `ORDER_PLACED` / `PAYMENT_SUCCESS` / `OUT_FOR_DELIVERY` / … |
| `payload`    | JSONB       | Full event body the service consumed from NATS |
| `sent_at`    | TIMESTAMPTZ | When the notification was dispatched |

```bash
# All notifications, newest first
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT id, user_id, channel, type, sent_at
      FROM notifications.notifications ORDER BY sent_at DESC LIMIT 50;"

# Total notifications dispatched
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT COUNT(*) AS total FROM notifications.notifications;"

# Mix by channel
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT channel, COUNT(*) FROM notifications.notifications GROUP BY channel;"

# Mix by event type
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT type, COUNT(*) FROM notifications.notifications GROUP BY type ORDER BY 2 DESC;"

# Full JSON payload of the most recent notification
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT type, jsonb_pretty(payload) AS payload
      FROM notifications.notifications ORDER BY sent_at DESC LIMIT 1;"

# Notifications for one user (replace USER_UUID)
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT type, channel, sent_at FROM notifications.notifications
      WHERE user_id = 'USER_UUID' ORDER BY sent_at DESC;"
```

---

## Useful Dashboard Queries

A single one-liner per topic — paste any of these to get an instant
"how's the app doing" snapshot.

```bash
# ─── Total accounts ──────────────────────────────────────────────
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT COUNT(*) AS registered_users FROM auth.users;"

# ─── Catalog size: restaurants + menu items ──────────────────────
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT (SELECT COUNT(*) FROM restaurants.restaurants) AS restaurants,
             (SELECT COUNT(*) FROM menu.menu_items)          AS menu_items,
             (SELECT COUNT(*) FROM menu.categories)          AS categories;"

# ─── Order funnel ────────────────────────────────────────────────
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT status, COUNT(*) AS orders, SUM(total) AS gmv
      FROM orders.orders GROUP BY status ORDER BY orders DESC;"

# ─── Money: collected vs failed ──────────────────────────────────
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT status, COUNT(*) AS attempts, SUM(amount) AS amount
      FROM payments.payments GROUP BY status;"

# ─── Delivery fleet utilisation ──────────────────────────────────
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT
        (SELECT COUNT(*) FROM delivery.agents WHERE available = true)  AS idle_agents,
        (SELECT COUNT(*) FROM delivery.agents WHERE available = false) AS busy_agents,
        (SELECT COUNT(*) FROM delivery.deliveries WHERE status = 'DELIVERED') AS completed;"

# ─── Row count of every table at once ────────────────────────────
kubectl exec -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen \
  -c "SELECT schemaname, relname AS table, n_live_tup AS rows
      FROM pg_stat_user_tables
      WHERE schemaname IN ('auth','users','restaurants','menu','orders','payments','delivery','notifications')
      ORDER BY schemaname, relname;"
```

The last query is the **single most useful sanity check** after a
deploy — it shows row counts for all 12 tables. A fresh cluster should
print:

```
 schemaname    | table         | rows
 auth          | users         |   0
 delivery      | agents        |  10    ← pre-seeded
 delivery      | deliveries    |   0
 menu          | categories    |   0
 menu          | menu_items    |   0
 notifications | notifications |   0
 orders        | order_items   |   0
 orders        | orders        |   0
 payments      | payments      |   0
 restaurants   | restaurants   |   0
 users         | addresses     |   0
 users         | profiles      |   0
```

After a full smoke-test flow (signup → add restaurant → add menu → cart
→ order → pay), every table except `delivery.deliveries` (if you didn't
manually advance status) should show ≥ 1 row.

---

## Quick Copy-Paste: Interactive Shell Session

If you'd rather poke around freely, open one shell and switch schemas
with `SET search_path`:

```bash
kubectl exec -it -n cloudkitchen postgres-0 -- \
  psql -U cloudkitchen -d cloudkitchen
```

Inside `psql`:

```sql
-- See the layout
\dn
\dt *.*

-- Auth
SET search_path TO auth;
SELECT * FROM users;

-- Profiles + addresses
SET search_path TO users;
SELECT * FROM profiles;
SELECT * FROM addresses;

-- Restaurants
SET search_path TO restaurants;
SELECT * FROM restaurants;

-- Menus
SET search_path TO menu;
SELECT * FROM categories;
SELECT * FROM menu_items;

-- Orders
SET search_path TO orders;
SELECT * FROM orders;
SELECT * FROM order_items;

-- Payments
SET search_path TO payments;
SELECT * FROM payments;

-- Delivery
SET search_path TO delivery;
SELECT * FROM agents;
SELECT * FROM deliveries;

-- Notifications
SET search_path TO notifications;
SELECT * FROM notifications;

\q
```

---

## Connection Details (Reference)

| Setting        | Value                                                  |
|----------------|--------------------------------------------------------|
| Host (in-cluster) | `postgres.cloudkitchen.svc.cluster.local` (or just `postgres` from within the namespace) |
| Port            | `5432`                                                |
| Username        | `cloudkitchen`                                        |
| Password        | `cloudkitchen-dev-password` (default — see [helm/cloudkitchen/values.yaml](../../helm/cloudkitchen/values.yaml) → `secrets.dbPassword`) |
| Database        | `cloudkitchen`                                        |
| Pod Name        | `postgres-0`                                          |
| Namespace       | `cloudkitchen`                                        |
| StatefulSet     | `postgres`                                            |
| PVC             | `data-postgres-0` (10 Gi by default — see chart values) |
| Schemas         | `auth`, `users`, `restaurants`, `menu`, `orders`, `payments`, `delivery`, `notifications` |
| Tables          | 12 total (see breakdown table at the top of this doc) |

> 🔐 **Heads-up: the password is a dev default**
> `cloudkitchen-dev-password` is fine for a learning cluster but is
> stored in plaintext under `secrets.dbPassword` in the chart values.
> For production, swap this out for a real Secret (External Secrets
> Operator + Google Secret Manager, or `kubectl create secret` ahead of
> the chart, with `secrets.create=false`).

---

## Connecting from Your Laptop (Optional)

If you'd rather use a GUI tool like **DBeaver**, **TablePlus**, or
`psql` on your laptop instead of `kubectl exec`, port-forward the
service:

```bash
# Forward in-cluster :5432 to your laptop's :5433 (avoid local conflicts)
kubectl -n cloudkitchen port-forward svc/postgres 5433:5432
```

Then in your GUI:

| Setting   | Value                          |
|-----------|--------------------------------|
| Host      | `localhost`                    |
| Port      | `5433`                         |
| Database  | `cloudkitchen`                 |
| Username  | `cloudkitchen`                 |
| Password  | `cloudkitchen-dev-password`    |

Press `Ctrl-C` in the `port-forward` terminal to stop forwarding.
