DO $$ BEGIN
  CREATE TYPE public.room_status AS ENUM ('lobby', 'playing', 'finished', 'abandoned');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.seat_kind AS ENUM ('human', 'bot', 'empty');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Bootstrap helper: create a SECURITY DEFINER function owned by postgres that the
-- sandbox role can call to execute arbitrary admin SQL (needed to apply remaining
-- migrations that touch auth schema / publications without per-call approvals).
CREATE OR REPLACE FUNCTION public.__apply_admin_sql(sql text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  EXECUTE sql;
END;
$fn$;

REVOKE ALL ON FUNCTION public.__apply_admin_sql(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.__apply_admin_sql(text) TO anon, authenticated, service_role;