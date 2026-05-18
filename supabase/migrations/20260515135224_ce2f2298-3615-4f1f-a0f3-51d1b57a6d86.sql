CREATE TABLE IF NOT EXISTS public.profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  friend_code text NOT NULL UNIQUE,
  avatar_url text,
  email text,
  username text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profiles_username_format CHECK (username IS NULL OR username ~ '^[a-z][a-z0-9_]{2,19}$')
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "profiles_select_authenticated" ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "profiles_update_self" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "profiles_no_client_insert" ON public.profiles FOR INSERT TO authenticated, anon WITH CHECK (false);
CREATE POLICY "profiles_no_client_delete" ON public.profiles FOR DELETE TO authenticated, anon USING (false);
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower_unique ON public.profiles (lower(username)) WHERE username IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.user_stats (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  wins integer NOT NULL DEFAULT 0,
  losses integer NOT NULL DEFAULT 0,
  abandoned integer NOT NULL DEFAULT 0,
  current_streak integer NOT NULL DEFAULT 0,
  max_streak integer NOT NULL DEFAULT 0,
  xp integer NOT NULL DEFAULT 0,
  level integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_stats ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_stats_select_authenticated" ON public.user_stats FOR SELECT TO authenticated USING (true);
CREATE POLICY "user_stats_no_client_write" ON public.user_stats FOR ALL TO authenticated, anon USING (false) WITH CHECK (false);

CREATE TABLE IF NOT EXISTS public.friendships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_b uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT friendships_pair_order CHECK (user_a < user_b),
  CONSTRAINT friendships_unique_pair UNIQUE (user_a, user_b)
);
CREATE INDEX IF NOT EXISTS friendships_user_a_idx ON public.friendships(user_a);
CREATE INDEX IF NOT EXISTS friendships_user_b_idx ON public.friendships(user_b);
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
CREATE POLICY "friendships_select_involved" ON public.friendships FOR SELECT TO authenticated USING (auth.uid() = user_a OR auth.uid() = user_b);
CREATE POLICY "friendships_no_client_write" ON public.friendships FOR ALL TO authenticated, anon USING (false) WITH CHECK (false);

CREATE OR REPLACE FUNCTION public.gen_friend_code()
RETURNS text LANGUAGE plpgsql SET search_path = public AS $$
DECLARE alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; candidate text; attempts int := 0;
BEGIN
  LOOP
    candidate := '';
    FOR i IN 1..8 LOOP candidate := candidate || substr(alphabet, 1 + floor(random()*length(alphabet))::int, 1); END LOOP;
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE friend_code = candidate) THEN RETURN candidate; END IF;
    attempts := attempts + 1;
    IF attempts > 20 THEN candidate := candidate || substr(md5(random()::text), 1, 4); RETURN candidate; END IF;
  END LOOP;
END; $$;

CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE display text;
BEGIN
  display := COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'display_name', ''),
    NULLIF(NEW.raw_user_meta_data->>'full_name', ''),
    NULLIF(NEW.raw_user_meta_data->>'name', ''),
    split_part(NEW.email, '@', 1),
    'Jugador'
  );
  INSERT INTO public.profiles (user_id, display_name, friend_code, email)
  VALUES (NEW.id, display, public.gen_friend_code(), NEW.email)
  ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.user_stats (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS user_stats_updated_at ON public.user_stats;
CREATE TRIGGER user_stats_updated_at BEFORE UPDATE ON public.user_stats FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS friendships_updated_at ON public.friendships;
CREATE TRIGGER friendships_updated_at BEFORE UPDATE ON public.friendships FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.level_for_xp(p_xp integer)
RETURNS integer LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
DECLARE lvl integer := 1; threshold integer := 0;
BEGIN
  IF p_xp IS NULL OR p_xp <= 0 THEN RETURN 1; END IF;
  LOOP
    threshold := threshold + lvl * 100;
    IF p_xp < threshold THEN RETURN lvl; END IF;
    lvl := lvl + 1;
    IF lvl > 999 THEN RETURN lvl; END IF;
  END LOOP;
END; $$;

CREATE OR REPLACE FUNCTION public.record_match_result(p_won boolean, p_human_opponents integer, p_bot_opponents integer)
RETURNS public.user_stats LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); base_xp integer; opp_xp integer; total_xp integer; result public.user_stats;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_human_opponents IS NULL OR p_human_opponents < 0 THEN p_human_opponents := 0; END IF;
  IF p_bot_opponents IS NULL OR p_bot_opponents < 0 THEN p_bot_opponents := 0; END IF;
  IF p_human_opponents + p_bot_opponents > 3 THEN p_bot_opponents := GREATEST(0, 3 - p_human_opponents); END IF;
  IF p_won THEN base_xp := 50; ELSE base_xp := 10; END IF;
  IF p_won THEN opp_xp := p_human_opponents * 20 + p_bot_opponents * 10;
  ELSE opp_xp := p_human_opponents * 5 + p_bot_opponents * 2; END IF;
  total_xp := base_xp + opp_xp;
  INSERT INTO public.user_stats (user_id, wins, losses, current_streak, max_streak, xp, level)
  VALUES (uid, CASE WHEN p_won THEN 1 ELSE 0 END, CASE WHEN p_won THEN 0 ELSE 1 END,
    CASE WHEN p_won THEN 1 ELSE 0 END, CASE WHEN p_won THEN 1 ELSE 0 END,
    total_xp, public.level_for_xp(total_xp))
  ON CONFLICT (user_id) DO UPDATE SET
    wins = public.user_stats.wins + (CASE WHEN p_won THEN 1 ELSE 0 END),
    losses = public.user_stats.losses + (CASE WHEN p_won THEN 0 ELSE 1 END),
    current_streak = CASE WHEN p_won THEN public.user_stats.current_streak + 1 ELSE 0 END,
    max_streak = GREATEST(public.user_stats.max_streak, CASE WHEN p_won THEN public.user_stats.current_streak + 1 ELSE public.user_stats.max_streak END),
    xp = public.user_stats.xp + total_xp,
    level = public.level_for_xp(public.user_stats.xp + total_xp),
    updated_at = now()
  RETURNING * INTO result;
  RETURN result;
END; $$;
GRANT EXECUTE ON FUNCTION public.record_match_result(boolean, integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.send_friend_request_by_code(p_code text)
RETURNS public.friendships LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); target uuid; ua uuid; ub uuid; result public.friendships;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN RAISE EXCEPTION 'invalid_code'; END IF;
  SELECT user_id INTO target FROM public.profiles WHERE friend_code = upper(trim(p_code));
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
GRANT EXECUTE ON FUNCTION public.send_friend_request_by_code(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.send_friend_request_by_email(p_email text)
RETURNS public.friendships LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); target uuid; ua uuid; ub uuid; result public.friendships;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT user_id INTO target FROM public.profiles WHERE lower(email) = lower(trim(p_email));
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
GRANT EXECUTE ON FUNCTION public.send_friend_request_by_email(text) TO authenticated;

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

CREATE OR REPLACE FUNCTION public.get_public_player_profile_by_device(p_device_id text)
RETURNS TABLE (user_id uuid, username text, display_name text, avatar_url text, friend_code text, level integer, xp integer, wins integer, losses integer, abandoned integer, current_streak integer, max_streak integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.user_id, p.username, p.display_name, p.avatar_url, p.friend_code,
    COALESCE(s.level,1), COALESCE(s.xp,0), COALESCE(s.wins,0), COALESCE(s.losses,0),
    COALESCE(s.abandoned,0), COALESCE(s.current_streak,0), COALESCE(s.max_streak,0)
  FROM public.account_links al
  JOIN public.profiles p ON p.user_id = al.user_id
  LEFT JOIN public.user_stats s ON s.user_id = al.user_id
  WHERE al.device_id = p_device_id LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_public_player_profile_by_device(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_public_avatars_by_devices(p_device_ids text[])
RETURNS TABLE (device_id text, avatar_url text, username text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT al.device_id, p.avatar_url, p.username
  FROM public.account_links al
  JOIN public.profiles p ON p.user_id = al.user_id
  WHERE al.device_id = ANY(p_device_ids);
$$;
GRANT EXECUTE ON FUNCTION public.get_public_avatars_by_devices(text[]) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_public_friends_by_user_id(p_user_id uuid)
RETURNS TABLE(user_id uuid, username text, display_name text, avatar_url text, level integer, wins integer, max_streak integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
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

CREATE OR REPLACE FUNCTION public.get_public_player_profile_by_user_id(p_user_id uuid)
RETURNS TABLE(user_id uuid, username text, display_name text, avatar_url text, friend_code text, level integer, xp integer, wins integer, losses integer, abandoned integer, current_streak integer, max_streak integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.user_id, p.username, p.display_name, p.avatar_url, p.friend_code,
    COALESCE(s.level,1), COALESCE(s.xp,0), COALESCE(s.wins,0),
    COALESCE(s.losses,0), COALESCE(s.abandoned,0),
    COALESCE(s.current_streak,0), COALESCE(s.max_streak,0)
  FROM public.profiles p
  LEFT JOIN public.user_stats s ON s.user_id = p.user_id
  WHERE p.user_id = p_user_id LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_public_player_profile_by_user_id(uuid) TO anon, authenticated;

INSERT INTO storage.buckets (id, name, public) VALUES ('avatars','avatars',true) ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
CREATE POLICY "avatars_public_read" ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
DROP POLICY IF EXISTS "avatars_authenticated_upload" ON storage.objects;
CREATE POLICY "avatars_authenticated_upload" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);
DROP POLICY IF EXISTS "avatars_authenticated_update" ON storage.objects;
CREATE POLICY "avatars_authenticated_update" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);
DROP POLICY IF EXISTS "avatars_authenticated_delete" ON storage.objects;
CREATE POLICY "avatars_authenticated_delete" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'avatars' AND auth.uid()::text = (storage.foldername(name))[1]);