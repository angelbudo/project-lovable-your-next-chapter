-- Delta migration: username + abandoned + social RPCs

ALTER TABLE public.user_stats ADD COLUMN IF NOT EXISTS abandoned integer NOT NULL DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS username text;
ALTER TABLE public.room_chat ADD COLUMN IF NOT EXISTS vars jsonb;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower_unique
  ON public.profiles (lower(username))
  WHERE username IS NOT NULL;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_username_format;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_username_format
  CHECK (username IS NULL OR username ~ '^[a-z][a-z0-9_]{2,19}$');

CREATE OR REPLACE FUNCTION public.is_username_reserved(p_username text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT lower(p_username) = ANY (ARRAY[
    'admin','administrator','root','support','help','moderator','mod',
    'system','staff','official','truc','lovable','null','undefined',
    'anonymous','anonim','jugador','user','users','me','you'
  ]);
$$;

CREATE OR REPLACE FUNCTION public.is_username_available(p_username text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE uname text := lower(trim(p_username));
BEGIN
  IF uname IS NULL OR uname !~ '^[a-z][a-z0-9_]{2,19}$' THEN RETURN false; END IF;
  IF public.is_username_reserved(uname) THEN RETURN false; END IF;
  RETURN NOT EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = uname);
END; $$;

CREATE OR REPLACE FUNCTION public.set_username(p_username text)
RETURNS public.profiles LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); uname text := lower(trim(p_username)); result public.profiles;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF uname IS NULL OR length(uname) = 0 THEN RAISE EXCEPTION 'invalid_username'; END IF;
  IF uname !~ '^[a-z][a-z0-9_]{2,19}$' THEN RAISE EXCEPTION 'invalid_format'; END IF;
  IF public.is_username_reserved(uname) THEN RAISE EXCEPTION 'reserved_username'; END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = uname AND user_id <> uid) THEN
    RAISE EXCEPTION 'username_taken';
  END IF;
  UPDATE public.profiles SET username = uname, updated_at = now()
    WHERE user_id = uid RETURNING * INTO result;
  IF NOT FOUND THEN RAISE EXCEPTION 'profile_not_found'; END IF;
  RETURN result;
END; $$;

GRANT EXECUTE ON FUNCTION public.is_username_available(text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.set_username(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.respond_friend_request(p_friendship_id uuid, p_accept boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); fr public.friendships;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO fr FROM public.friendships WHERE id = p_friendship_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF uid <> fr.user_a AND uid <> fr.user_b THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF fr.requested_by = uid THEN RAISE EXCEPTION 'cannot_self_respond'; END IF;
  IF p_accept THEN UPDATE public.friendships SET status = 'accepted', updated_at = now() WHERE id = p_friendship_id;
  ELSE DELETE FROM public.friendships WHERE id = p_friendship_id; END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.respond_friend_request(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.remove_friend(p_friend_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); ua uuid; ub uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF uid < p_friend_user_id THEN ua := uid; ub := p_friend_user_id; ELSE ua := p_friend_user_id; ub := uid; END IF;
  DELETE FROM public.friendships WHERE user_a = ua AND user_b = ub;
END; $$;
GRANT EXECUTE ON FUNCTION public.remove_friend(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.send_friend_request_by_username(p_username text)
RETURNS public.friendships LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); uname text := lower(trim(p_username)); target uuid; ua uuid; ub uuid; result public.friendships;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF uname IS NULL OR length(uname) = 0 THEN RAISE EXCEPTION 'invalid_username'; END IF;
  SELECT user_id INTO target FROM public.profiles WHERE lower(username) = uname;
  IF target IS NULL THEN RAISE EXCEPTION 'user_not_found'; END IF;
  IF target = uid THEN RAISE EXCEPTION 'cannot_friend_self'; END IF;
  IF uid < target THEN ua := uid; ub := target; ELSE ua := target; ub := uid; END IF;
  INSERT INTO public.friendships (user_a, user_b, requested_by, status) VALUES (ua, ub, uid, 'pending')
  ON CONFLICT (user_a, user_b) DO UPDATE SET status = CASE
    WHEN public.friendships.status = 'pending' AND public.friendships.requested_by <> EXCLUDED.requested_by THEN 'accepted'
    ELSE public.friendships.status END, updated_at = now()
  RETURNING * INTO result;
  RETURN result;
END; $$;
GRANT EXECUTE ON FUNCTION public.send_friend_request_by_username(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_public_player_profile_by_device(p_device_id text)
RETURNS TABLE (
  user_id uuid, username text, display_name text, avatar_url text, friend_code text,
  level integer, xp integer, wins integer, losses integer, abandoned integer,
  current_streak integer, max_streak integer
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.user_id, p.username, p.display_name, p.avatar_url, p.friend_code,
    COALESCE(s.level,1), COALESCE(s.xp,0), COALESCE(s.wins,0), COALESCE(s.losses,0),
    COALESCE(s.abandoned,0), COALESCE(s.current_streak,0), COALESCE(s.max_streak,0)
  FROM public.account_links al
  JOIN public.profiles p ON p.user_id = al.user_id
  LEFT JOIN public.user_stats s ON s.user_id = al.user_id
  WHERE al.device_id = p_device_id LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_public_player_profile_by_device(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_public_player_profile_by_user_id(p_user_id uuid)
RETURNS TABLE(
  user_id uuid, username text, display_name text, avatar_url text, friend_code text,
  level integer, xp integer, wins integer, losses integer, abandoned integer,
  current_streak integer, max_streak integer
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.user_id, p.username, p.display_name, p.avatar_url, p.friend_code,
    COALESCE(s.level,1), COALESCE(s.xp,0), COALESCE(s.wins,0), COALESCE(s.losses,0),
    COALESCE(s.abandoned,0), COALESCE(s.current_streak,0), COALESCE(s.max_streak,0)
  FROM public.profiles p
  LEFT JOIN public.user_stats s ON s.user_id = p.user_id
  WHERE p.user_id = p_user_id LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_public_player_profile_by_user_id(uuid) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_public_friends_by_user_id(p_user_id uuid)
RETURNS TABLE(
  user_id uuid, username text, display_name text, avatar_url text,
  level integer, wins integer, max_streak integer
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH fr AS (
    SELECT CASE WHEN user_a = p_user_id THEN user_b ELSE user_a END AS friend_id
    FROM public.friendships
    WHERE status = 'accepted' AND (user_a = p_user_id OR user_b = p_user_id)
  )
  SELECT p.user_id, p.username, p.display_name, p.avatar_url,
    COALESCE(s.level,1), COALESCE(s.wins,0), COALESCE(s.max_streak,0)
  FROM fr
  JOIN public.profiles p ON p.user_id = fr.friend_id
  LEFT JOIN public.user_stats s ON s.user_id = fr.friend_id
  ORDER BY COALESCE(s.level,1) DESC, COALESCE(s.wins,0) DESC;
$$;
GRANT EXECUTE ON FUNCTION public.get_public_friends_by_user_id(uuid) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_public_avatars_by_devices(p_device_ids text[])
RETURNS TABLE (device_id text, avatar_url text, username text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT al.device_id, p.avatar_url, p.username
  FROM public.account_links al
  JOIN public.profiles p ON p.user_id = al.user_id
  WHERE al.device_id = ANY(p_device_ids);
$$;
GRANT EXECUTE ON FUNCTION public.get_public_avatars_by_devices(text[]) TO anon, authenticated;