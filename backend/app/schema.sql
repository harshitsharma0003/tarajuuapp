-- Tarajuu schema. Idempotent: applied on every API start-up.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    phone       text UNIQUE,
    name        text,
    email       text,
    firebase_uid text UNIQUE,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- One row per real-world product; Amazon and Flipkart listings of the same
-- item are merged onto the same row by the matcher.
CREATE TABLE IF NOT EXISTS products (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title              text NOT NULL,
    brand              text,
    category           text,
    image_url          text,
    images             jsonb NOT NULL DEFAULT '[]'::jsonb,
    amazon_asin        text UNIQUE,
    amazon_price       int,
    amazon_mrp         int,
    amazon_url         text,
    amazon_rating      real,
    amazon_reviews     int,
    flipkart_pid       text UNIQUE,
    flipkart_price     int,
    flipkart_mrp       int,
    flipkart_url       text,
    flipkart_rating    real,
    flipkart_reviews   int,
    details_fetched_at timestamptz,
    updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS price_history (
    id          bigserial PRIMARY KEY,
    product_id  uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    source      text NOT NULL,
    price       int NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS price_history_product_idx ON price_history (product_id, recorded_at DESC);

CREATE TABLE IF NOT EXISTS search_cache (
    query_norm  text PRIMARY KEY,
    product_ids uuid[] NOT NULL,
    sources     jsonb NOT NULL,
    fetched_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS search_history (
    id         bigserial PRIMARY KEY,
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind       text NOT NULL CHECK (kind IN ('product', 'ride')),
    query      text NOT NULL,
    title      text NOT NULL,
    subtitle   text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS search_history_user_idx ON search_history (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS favourites (
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, product_id)
);

-- "Buy" taps; saved_amount powers the "₹240 saved" badge on Home.
CREATE TABLE IF NOT EXISTS buy_clicks (
    id           bigserial PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id   uuid REFERENCES products(id) ON DELETE SET NULL,
    kind         text NOT NULL DEFAULT 'product',
    source       text NOT NULL,
    saved_amount int NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now()
);

-- Scrape jobs handed to the local scrape agent (SCRAPE_MODE=agent).
CREATE TABLE IF NOT EXISTS scrape_jobs (
    id          bigserial PRIMARY KEY,
    kind        text NOT NULL,
    args        jsonb NOT NULL,
    status      text NOT NULL DEFAULT 'queued',  -- queued | running | done | error | expired
    result      jsonb,
    created_at  timestamptz NOT NULL DEFAULT now(),
    claimed_at  timestamptz,
    finished_at timestamptz
);
CREATE INDEX IF NOT EXISTS scrape_jobs_queued_idx ON scrape_jobs (id) WHERE status = 'queued';

-- Rides booked through a provider API (Uber Guest Rides).
CREATE TABLE IF NOT EXISTS ride_bookings (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider    text NOT NULL,
    request_id  text NOT NULL,
    product     text,
    fare        int,
    pickup      jsonb NOT NULL,
    dropoff     jsonb NOT NULL,
    status      text NOT NULL DEFAULT 'processing',
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ride_bookings_user_idx ON ride_bookings (user_id, created_at DESC);
