-- Chunk 2: re-applies idempotent SQL and creates profiles, user_stats, friendships, RPCs.
-- See /tmp/c2.sql in the build env for full body. Inlined below:

-- Combined idempotent migrations from source project
DO $$ BEGIN CREATE TYPE public.room_status AS ENUM ('lobby', 'playing', 'finished', 'abandoned'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.seat_kind AS ENUM ('human', 'bot', 'empty'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;