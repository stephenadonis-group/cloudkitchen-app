-- ==========================================================================
-- CloudKitchen demo seed
-- --------------------------------------------------------------------------
-- Populates the LIVE database with 20 restaurants and ~100 menu items so the
-- customer UI at http://vijaygiduthuri.in/ has content to browse.
--
-- Idempotent: DELETEs any previously seeded data owned by the demo owner,
-- then re-inserts the full catalogue. Safe to re-run any time.
--
-- Data model:
--   * All 20 restaurants share a synthetic "demo owner" UUID. Real users'
--     restaurants (if any) are untouched.
--   * Each restaurant gets 2-3 categories.
--   * Each category gets 2-4 items.
--
-- Apply via:
--   kubectl -n cloudkitchen exec -i postgres-0 -- psql -U cloudkitchen \
--     -d cloudkitchen < scripts/seed-restaurants.sql
-- ==========================================================================

DO $$
DECLARE
  demo_owner CONSTANT UUID := '00000000-0000-4000-8000-000000000001';
  rest_id UUID;
  cat_id  UUID;
BEGIN

  -- ------------------------------------------------------------------------
  -- 0. Idempotent wipe of previously seeded demo data.
  --    Deletes ONLY the demo owner's rows; any real user data survives.
  -- ------------------------------------------------------------------------
  DELETE FROM menu.menu_items
   WHERE restaurant_id IN (SELECT id FROM restaurants.restaurants WHERE owner_id = demo_owner);
  DELETE FROM menu.categories
   WHERE restaurant_id IN (SELECT id FROM restaurants.restaurants WHERE owner_id = demo_owner);
  DELETE FROM restaurants.restaurants WHERE owner_id = demo_owner;

  -- ========================================================================
  -- Restaurant 1 — Vijay's Pizza (Hyderabad, Italian)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Vijay''s Pizza',
            'Authentic wood-fired Italian pizzas, hand-tossed daily',
            '1 MG Road', 'Hyderabad', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Pizzas') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Margherita Pizza',   'Classic tomato & mozzarella',        250, true),
    (gen_random_uuid(), rest_id, cat_id, 'Pepperoni Pizza',    'Loaded with spicy pepperoni',        350, true),
    (gen_random_uuid(), rest_id, cat_id, 'BBQ Chicken Pizza',  'Smoky BBQ chicken + red onions',     400, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Sides') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Garlic Bread',       'Buttery garlic bread with cheese',   120, true),
    (gen_random_uuid(), rest_id, cat_id, 'Cheese Sticks',      'Fried mozzarella sticks',            180, true);

  -- ========================================================================
  -- Restaurant 2 — Spice Route (Bangalore, North Indian)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Spice Route',
            'North Indian classics slow-cooked with 30+ hand-ground spices',
            '12 Brigade Road', 'Bangalore', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Mains') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Butter Chicken',       'Tandoori chicken in silky tomato gravy',     380, true),
    (gen_random_uuid(), rest_id, cat_id, 'Paneer Tikka Masala',  'Grilled paneer in rich makhani gravy',       320, true),
    (gen_random_uuid(), rest_id, cat_id, 'Rogan Josh',           'Kashmiri mutton curry with red chilli',      420, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Breads') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Butter Naan',          'Freshly baked naan brushed with butter',      60, true),
    (gen_random_uuid(), rest_id, cat_id, 'Garlic Roti',          'Tandoor-baked whole wheat roti',              50, true);

  -- ========================================================================
  -- Restaurant 3 — Dragon Wok (Mumbai, Chinese)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Dragon Wok',
            'Indo-Chinese comfort food served hot from the wok',
            '5 Linking Road', 'Mumbai', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Noodles') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Hakka Noodles',        'Stir-fried veg hakka noodles',        220, true),
    (gen_random_uuid(), rest_id, cat_id, 'Chicken Chow Mein',    'Wok-tossed chicken chow mein',        280, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Rice') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Veg Fried Rice',       'Classic fried rice with vegetables',  200, true),
    (gen_random_uuid(), rest_id, cat_id, 'Schezwan Chicken Rice','Spicy schezwan chicken rice',         290, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Starters') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Chilli Chicken',       'Boneless chicken in chilli sauce',    260, true),
    (gen_random_uuid(), rest_id, cat_id, 'Veg Spring Rolls',     'Crispy rolls stuffed with veggies',   140, true);

  -- ========================================================================
  -- Restaurant 4 — Taco Fiesta (Delhi, Mexican)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Taco Fiesta',
            'Mexican street food — tacos, nachos, and quesadillas',
            '17 Connaught Place', 'Delhi', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Tacos') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Chicken Taco',         'Grilled chicken, salsa, cheese',      180, true),
    (gen_random_uuid(), rest_id, cat_id, 'Paneer Taco',          'Spiced paneer, lettuce, salsa',       170, true),
    (gen_random_uuid(), rest_id, cat_id, 'Beans & Corn Taco',    'Rajma & corn with lime crema',        150, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Sides') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Loaded Nachos',        'Nachos with cheese, jalapeños, salsa',210, true),
    (gen_random_uuid(), rest_id, cat_id, 'Guacamole & Chips',    'Fresh avocado dip with tortilla chips',190, true);

  -- ========================================================================
  -- Restaurant 5 — Sushi Zen (Hyderabad, Japanese)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Sushi Zen',
            'Fresh sushi rolls and Japanese comfort bowls',
            '9 Banjara Hills', 'Hyderabad', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Sushi Rolls') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'California Roll',      'Crab, avocado, cucumber (8 pcs)',     450, true),
    (gen_random_uuid(), rest_id, cat_id, 'Salmon Nigiri',        'Sushi rice topped with salmon (6 pcs)',520, true),
    (gen_random_uuid(), rest_id, cat_id, 'Veggie Roll',          'Avocado, carrot, cucumber (8 pcs)',   380, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Bowls') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Chicken Teriyaki Bowl','Grilled chicken teriyaki over rice',  380, true),
    (gen_random_uuid(), rest_id, cat_id, 'Shoyu Ramen',          'Rich soy-based broth, noodles, egg',  340, true);

  -- ========================================================================
  -- Restaurant 6 — Burger Hub (Chennai, American)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Burger Hub',
            'Juicy handcrafted burgers on brioche buns',
            '22 Anna Salai', 'Chennai', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Burgers') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Classic Cheeseburger', 'Beef patty, cheddar, lettuce, tomato',280, true),
    (gen_random_uuid(), rest_id, cat_id, 'BBQ Bacon Burger',     'Bacon, BBQ sauce, cheddar, onions',   340, true),
    (gen_random_uuid(), rest_id, cat_id, 'Veggie Deluxe',        'Mushroom & lentil patty, avocado',    260, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Sides') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'French Fries',         'Crispy salted fries',                 120, true),
    (gen_random_uuid(), rest_id, cat_id, 'Onion Rings',          'Battered onion rings, 8 pcs',         150, true);

  -- ========================================================================
  -- Restaurant 7 — Bangkok Nights (Pune, Thai)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Bangkok Nights',
            'Authentic Thai curries, wok-tossed noodles, and satay',
            '4 Koregaon Park', 'Pune', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Curries') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Thai Green Curry',     'Chicken in aromatic green curry paste',360, true),
    (gen_random_uuid(), rest_id, cat_id, 'Red Curry Prawns',     'Prawns in red curry with basil',      420, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Noodles') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Pad Thai Chicken',     'Rice noodles, peanut, chicken',       320, true),
    (gen_random_uuid(), rest_id, cat_id, 'Drunken Noodles',      'Flat noodles, basil, chilli, chicken',340, true);

  -- ========================================================================
  -- Restaurant 8 — Curry Palace (Kolkata, Bengali)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Curry Palace',
            'Bengali home-cooking — fish curry, thalis, and mishti',
            '8 Park Street', 'Kolkata', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Mains') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Macher Jhol',          'Bengali fish curry with potato',      340, true),
    (gen_random_uuid(), rest_id, cat_id, 'Bengali Veg Thali',    '5-item veg thali with rice and dal',  280, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Sweets') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Rasgulla (2 pcs)',     'Soft cottage cheese in syrup',         80, true),
    (gen_random_uuid(), rest_id, cat_id, 'Mishti Doi',           'Sweet caramelised curd',               90, true);

  -- ========================================================================
  -- Restaurant 9 — Pasta Paradise (Bangalore, Italian)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Pasta Paradise',
            'Fresh pastas, tossed to order in Roman-style sauces',
            '3 Church Street', 'Bangalore', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Pastas') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Spaghetti Carbonara',  'Bacon, egg, parmesan, black pepper',  340, true),
    (gen_random_uuid(), rest_id, cat_id, 'Penne Arrabiata',      'Spicy tomato garlic sauce',           300, true),
    (gen_random_uuid(), rest_id, cat_id, 'Chicken Lasagna',      'Layered pasta, béchamel, chicken ragu',380, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Salads') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Caesar Salad',         'Romaine, parmesan, croutons, dressing',260, true),
    (gen_random_uuid(), rest_id, cat_id, 'Caprese',              'Tomato, mozzarella, basil, olive oil',290, true);

  -- ========================================================================
  -- Restaurant 10 — BBQ Nation (Mumbai, American)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'BBQ Nation',
            'Charcoal-grilled BBQ favourites and slow-smoked meats',
            '11 Bandra West', 'Mumbai', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'From the Grill') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'BBQ Pork Ribs',        'Slow-smoked baby-back ribs',          520, true),
    (gen_random_uuid(), rest_id, cat_id, 'Grilled Chicken',      'Half chicken with smoky BBQ glaze',   380, true),
    (gen_random_uuid(), rest_id, cat_id, 'Lamb Chops',           'Char-grilled with herbs and lemon',   580, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Sides') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Coleslaw',             'Cabbage, carrot, creamy dressing',    120, true),
    (gen_random_uuid(), rest_id, cat_id, 'Corn on the Cob',      'Buttered corn with paprika',          140, true);

  -- ========================================================================
  -- Restaurant 11 — Noodle House (Hyderabad, Pan-Asian)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Noodle House',
            'Steaming bowls of ramen, pho, and hand-pulled noodles',
            '14 Jubilee Hills', 'Hyderabad', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Noodle Bowls') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Chicken Ramen',        'Shoyu broth, ramen noodles, chicken', 320, true),
    (gen_random_uuid(), rest_id, cat_id, 'Beef Pho',             'Vietnamese beef noodle soup',         340, true),
    (gen_random_uuid(), rest_id, cat_id, 'Veg Wok Noodles',      'Vegetables, garlic, soy',             240, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Dumplings') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Steamed Momos',        'Chicken momos (8 pcs)',               200, true),
    (gen_random_uuid(), rest_id, cat_id, 'Pan-Fried Gyoza',      'Veg gyoza with soy dip (6 pcs)',      220, true);

  -- ========================================================================
  -- Restaurant 12 — Kebab Corner (Delhi, Mughlai)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Kebab Corner',
            'Mughlai kebabs and biryanis grilled over charcoal',
            '6 Chandni Chowk', 'Delhi', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Kebabs') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Seekh Kebab',          'Minced mutton skewers (4 pcs)',       320, true),
    (gen_random_uuid(), rest_id, cat_id, 'Chicken Tikka',        'Boneless chicken in tandoori masala', 280, true),
    (gen_random_uuid(), rest_id, cat_id, 'Malai Kebab',          'Creamy chicken kebabs with cheese',   340, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Rice') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Chicken Biryani',      'Long-grain basmati, whole spices',    340, true),
    (gen_random_uuid(), rest_id, cat_id, 'Jeera Rice',           'Basmati rice tempered with cumin',    140, true);

  -- ========================================================================
  -- Restaurant 13 — Pizza Craze (Chennai, Italian)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Pizza Craze',
            'Loaded Indian-style pizzas with generous toppings',
            '19 Adyar', 'Chennai', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Pizzas') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Farmhouse Pizza',      'Onion, tomato, capsicum, mushroom',   320, true),
    (gen_random_uuid(), rest_id, cat_id, 'Mexican Green Wave',   'Jalapeño, olives, capsicum',          340, true),
    (gen_random_uuid(), rest_id, cat_id, 'Four Cheese Pizza',    'Mozzarella, cheddar, parmesan, feta', 420, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Sides') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Cheesy Dip',           'Warm cheese dip with breadsticks',    140, true),
    (gen_random_uuid(), rest_id, cat_id, 'Potato Wedges',        'Spicy wedges with peri-peri dust',    160, true);

  -- ========================================================================
  -- Restaurant 14 — Tandoor Express (Bangalore, Punjabi)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Tandoor Express',
            'Punjabi tandoori grills and dal makhani',
            '25 Indiranagar', 'Bangalore', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Tandoori') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Tandoori Chicken',     'Yogurt-marinated chicken, half',      340, true),
    (gen_random_uuid(), rest_id, cat_id, 'Tandoori Fish',        'Basa marinated in ajwain & lemon',    360, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Curries') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Dal Makhani',          'Slow-cooked black lentils, butter',   240, true),
    (gen_random_uuid(), rest_id, cat_id, 'Palak Paneer',         'Cottage cheese in spinach gravy',     260, true);

  -- ========================================================================
  -- Restaurant 15 — Dosa Junction (Chennai, South Indian)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Dosa Junction',
            'Crisp South Indian dosas, idlis, and filter coffee',
            '2 T Nagar', 'Chennai', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Dosas') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Masala Dosa',          'Crispy dosa with spiced potato filling',140, true),
    (gen_random_uuid(), rest_id, cat_id, 'Ghee Roast Dosa',      'Extra-crispy dosa roasted in pure ghee',160, true),
    (gen_random_uuid(), rest_id, cat_id, 'Onion Rava Dosa',      'Semolina dosa with sliced onions',    170, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Idli & More') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Idli-Sambhar',         'Steamed rice cakes (3 pcs) with sambhar',100, true),
    (gen_random_uuid(), rest_id, cat_id, 'Uttapam',              'Thick pancake with tomato & onion',   130, true);

  -- ========================================================================
  -- Restaurant 16 — Biryani Blues (Hyderabad, Hyderabadi)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Biryani Blues',
            'Slow-dum Hyderabadi biryanis in sealed handi pots',
            '7 Charminar Road', 'Hyderabad', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Biryanis') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Chicken Dum Biryani',  'Aromatic Hyderabadi chicken biryani',  340, true),
    (gen_random_uuid(), rest_id, cat_id, 'Mutton Biryani',       'Slow-cooked mutton with basmati',      440, true),
    (gen_random_uuid(), rest_id, cat_id, 'Veg Dum Biryani',      'Mixed vegetable biryani',              260, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Accompaniments') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Mirchi ka Salan',      'Green chilli curry with peanuts',      120, true),
    (gen_random_uuid(), rest_id, cat_id, 'Raita',                'Yogurt with onion & mint',              60, true);

  -- ========================================================================
  -- Restaurant 17 — Sweet Cravings (Mumbai, Dessert & Bakery)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Sweet Cravings',
            'Fresh-baked cakes, pastries, and hand-churned ice cream',
            '30 Juhu Beach Road', 'Mumbai', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Cakes & Pastries') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Chocolate Truffle Slice','Dark chocolate ganache slice',      160, true),
    (gen_random_uuid(), rest_id, cat_id, 'Red Velvet Cake Slice',  'Cream cheese frosting, moist crumb',180, true),
    (gen_random_uuid(), rest_id, cat_id, 'Blueberry Cheesecake',   'New York-style baked cheesecake',   220, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Ice Cream') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Belgian Chocolate Scoop','Rich dark chocolate ice cream',     140, true),
    (gen_random_uuid(), rest_id, cat_id, 'Alphonso Mango Scoop',   'Seasonal Alphonso mango sorbet',    150, true),
    (gen_random_uuid(), rest_id, cat_id, 'Vanilla Bean Scoop',     'Madagascar vanilla, cream base',    130, true);

  -- ========================================================================
  -- Restaurant 18 — Chaat Street (Delhi, Street Food)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Chaat Street',
            'Delhi street chaats and snacks — pani puri, tikki, and more',
            '15 Karol Bagh', 'Delhi', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Chaats') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Pani Puri (8 pcs)',     'Crisp puris with tangy mint water',   90, true),
    (gen_random_uuid(), rest_id, cat_id, 'Bhel Puri',             'Puffed rice, sev, chutneys',         100, true),
    (gen_random_uuid(), rest_id, cat_id, 'Dahi Puri',             'Puris filled with yogurt & chutneys',110, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Snacks') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Aloo Tikki (2 pcs)',    'Fried potato patties with chutneys',  90, true),
    (gen_random_uuid(), rest_id, cat_id, 'Samosa (2 pcs)',        'Crispy potato-stuffed samosas',       60, true);

  -- ========================================================================
  -- Restaurant 19 — Wok & Roll (Pune, Asian Fusion)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'Wok & Roll',
            'Pan-Asian bowls, bao buns, and wok-tossed rice',
            '18 Baner Road', 'Pune', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Rice Bowls') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Korean Kimchi Bowl',    'Kimchi, egg, sesame, chicken',       340, true),
    (gen_random_uuid(), rest_id, cat_id, 'Teriyaki Chicken Bowl', 'Teriyaki chicken, edamame, rice',    320, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Bao Buns') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Chicken Bao (2 pcs)',   'Steamed buns with braised chicken',  220, true),
    (gen_random_uuid(), rest_id, cat_id, 'Paneer Bao (2 pcs)',    'Steamed buns with spiced paneer',    200, true),
    (gen_random_uuid(), rest_id, cat_id, 'Edamame',               'Salted steamed edamame',             120, true);

  -- ========================================================================
  -- Restaurant 20 — The Green Bowl (Bangalore, Healthy)
  -- ========================================================================
  INSERT INTO restaurants.restaurants (id, owner_id, name, description, address, city, status)
    VALUES (gen_random_uuid(), demo_owner, 'The Green Bowl',
            'Fresh salads, grain bowls, and cold-pressed juices',
            '10 Koramangala 5th Block', 'Bangalore', 'active')
    RETURNING id INTO rest_id;
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Bowls & Salads') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Quinoa Power Bowl',     'Quinoa, chickpeas, avocado, feta',   280, true),
    (gen_random_uuid(), rest_id, cat_id, 'Greek Salad',           'Olives, feta, cucumber, tomato',     240, true),
    (gen_random_uuid(), rest_id, cat_id, 'Grilled Chicken Caesar','Romaine, grilled chicken, dressing', 300, true);
  INSERT INTO menu.categories (id, restaurant_id, name)
    VALUES (gen_random_uuid(), rest_id, 'Drinks') RETURNING id INTO cat_id;
  INSERT INTO menu.menu_items (id, restaurant_id, category_id, name, description, price, available) VALUES
    (gen_random_uuid(), rest_id, cat_id, 'Berry Smoothie',        'Blueberry, banana, yogurt',          180, true),
    (gen_random_uuid(), rest_id, cat_id, 'Mango Lassi',           'Sweet yogurt drink with Alphonso',   140, true);

END $$;

-- Post-seed summary
SELECT 'restaurants' AS tbl, COUNT(*) AS rows FROM restaurants.restaurants
UNION ALL SELECT 'categories',  COUNT(*) FROM menu.categories
UNION ALL SELECT 'menu_items',  COUNT(*) FROM menu.menu_items;
