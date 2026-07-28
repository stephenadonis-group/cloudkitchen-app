-- menu-service schema: categories and menu_items. Idempotent.
CREATE TABLE IF NOT EXISTS categories (
    id            UUID PRIMARY KEY,
    restaurant_id UUID NOT NULL,
    name          TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS menu_items (
    id            UUID PRIMARY KEY,
    restaurant_id UUID NOT NULL,
    category_id   UUID NOT NULL,
    name          TEXT NOT NULL,
    description   TEXT NOT NULL DEFAULT '',
    price         NUMERIC(10,2) NOT NULL,
    available     BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_categories_restaurant ON categories (restaurant_id);
CREATE INDEX IF NOT EXISTS idx_menu_items_restaurant ON menu_items (restaurant_id);
CREATE INDEX IF NOT EXISTS idx_menu_items_name ON menu_items (lower(name));
