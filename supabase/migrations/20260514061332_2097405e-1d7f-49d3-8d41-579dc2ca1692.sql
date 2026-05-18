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