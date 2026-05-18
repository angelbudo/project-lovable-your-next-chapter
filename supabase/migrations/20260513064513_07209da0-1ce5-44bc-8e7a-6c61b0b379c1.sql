-- Public lookup of a user's accepted friends (no PII)
CREATE OR REPLACE FUNCTION public.get_public_friends_by_user_id(p_user_id uuid)
RETURNS TABLE(
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  level integer,
  wins integer,
  max_streak integer
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
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

-- Public profile lookup by user_id (used when clicking on a friend in a dialog)
CREATE OR REPLACE FUNCTION public.get_public_player_profile_by_user_id(p_user_id uuid)
RETURNS TABLE(
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
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.user_id, p.username, p.display_name, p.avatar_url, p.friend_code,
    COALESCE(s.level,1), COALESCE(s.xp,0), COALESCE(s.wins,0),
    COALESCE(s.losses,0), COALESCE(s.abandoned,0),
    COALESCE(s.current_streak,0), COALESCE(s.max_streak,0)
  FROM public.profiles p
  LEFT JOIN public.user_stats s ON s.user_id = p.user_id
  WHERE p.user_id = p_user_id
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_public_player_profile_by_user_id(uuid) TO anon, authenticated;