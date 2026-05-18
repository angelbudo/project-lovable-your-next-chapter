CREATE OR REPLACE FUNCTION public.get_public_player_profile_by_device(p_device_id text)
RETURNS TABLE (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  friend_code text,
  level integer,
  xp integer,
  wins integer,
  losses integer,
  abandoned integer,
  current_streak integer,
  max_streak integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.user_id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.friend_code,
    COALESCE(s.level, 1) AS level,
    COALESCE(s.xp, 0) AS xp,
    COALESCE(s.wins, 0) AS wins,
    COALESCE(s.losses, 0) AS losses,
    COALESCE(s.abandoned, 0) AS abandoned,
    COALESCE(s.current_streak, 0) AS current_streak,
    COALESCE(s.max_streak, 0) AS max_streak
  FROM public.account_links al
  JOIN public.profiles p ON p.user_id = al.user_id
  LEFT JOIN public.user_stats s ON s.user_id = al.user_id
  WHERE al.device_id = p_device_id
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_player_profile_by_device(text) TO anon, authenticated;