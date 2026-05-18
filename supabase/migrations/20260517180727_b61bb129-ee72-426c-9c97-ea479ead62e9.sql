-- ===== 20260509214005 - Initial schema part 1 =====
DO $$ BEGIN
  CREATE TYPE public.room_status AS ENUM ('lobby', 'playing', 'finished', 'abandoned');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.seat_kind AS ENUM ('human', 'bot', 'empty');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  status public.room_status NOT NULL DEFAULT 'lobby',
  target_cames INTEGER NOT NULL DEFAULT 2 CHECK (target_cames BETWEEN 1 AND 5),
  initial_mano SMALLINT NOT NULL DEFAULT 0 CHECK (initial_mano BETWEEN 0 AND 3),
  seat_kinds public.seat_kind[] NOT NULL,
  host_device TEXT NOT NULL,
  match_state JSONB,
  bot_intents JSONB NOT NULL DEFAULT '{}'::jsonb,
  turn_started_at timestamptz,
  paused_at timestamptz,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SELECT 1;