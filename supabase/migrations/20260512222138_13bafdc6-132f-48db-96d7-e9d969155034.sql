-- Add username column (nullable to allow gradual adoption by existing users)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS username text;

-- Case-insensitive uniqueness
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower_unique
  ON public.profiles (lower(username))
  WHERE username IS NOT NULL;

-- Format check: 3-20 chars, lowercase letters / digits / underscore, must start with letter
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_username_format;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_username_format
  CHECK (username IS NULL OR username ~ '^[a-z][a-z0-9_]{2,19}$');

-- Reserved words that cannot be taken as username
CREATE OR REPLACE FUNCTION public.is_username_reserved(p_username text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT lower(p_username) = ANY (ARRAY[
    'admin','administrator','root','support','help','moderator','mod',
    'system','staff','official','truc','lovable','null','undefined',
    'anonymous','anonim','jugador','user','users','me','you'
  ]);
$$;

-- Check availability (returns true if free + valid)
CREATE OR REPLACE FUNCTION public.is_username_available(p_username text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uname text := lower(trim(p_username));
BEGIN
  IF uname IS NULL OR uname !~ '^[a-z][a-z0-9_]{2,19}$' THEN
    RETURN false;
  END IF;
  IF public.is_username_reserved(uname) THEN
    RETURN false;
  END IF;
  RETURN NOT EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = uname);
END;
$$;

-- Set/change own username
CREATE OR REPLACE FUNCTION public.set_username(p_username text)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  uname text := lower(trim(p_username));
  result public.profiles;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF uname IS NULL OR length(uname) = 0 THEN RAISE EXCEPTION 'invalid_username'; END IF;
  IF uname !~ '^[a-z][a-z0-9_]{2,19}$' THEN RAISE EXCEPTION 'invalid_format'; END IF;
  IF public.is_username_reserved(uname) THEN RAISE EXCEPTION 'reserved_username'; END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = uname AND user_id <> uid) THEN
    RAISE EXCEPTION 'username_taken';
  END IF;
  UPDATE public.profiles SET username = uname, updated_at = now()
    WHERE user_id = uid
    RETURNING * INTO result;
  IF NOT FOUND THEN RAISE EXCEPTION 'profile_not_found'; END IF;
  RETURN result;
END;
$$;