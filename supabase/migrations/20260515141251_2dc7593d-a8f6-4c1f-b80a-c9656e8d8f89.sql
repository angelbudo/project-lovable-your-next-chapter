DROP FUNCTION IF EXISTS public.get_public_friends_by_user_id(uuid);
CREATE FUNCTION public.get_public_friends_by_user_id(p_user_id uuid)
 RETURNS TABLE(user_id uuid, username text, display_name text, avatar_url text, level integer, wins integer, losses integer, max_streak integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH fr AS (
    SELECT CASE WHEN user_a = p_user_id THEN user_b ELSE user_a END AS friend_id
    FROM public.friendships
    WHERE status = 'accepted' AND (user_a = p_user_id OR user_b = p_user_id)
  )
  SELECT p.user_id, p.username, p.display_name, p.avatar_url,
         COALESCE(s.level,1), COALESCE(s.wins,0), COALESCE(s.losses,0), COALESCE(s.max_streak,0)
  FROM fr
  JOIN public.profiles p ON p.user_id = fr.friend_id
  LEFT JOIN public.user_stats s ON s.user_id = fr.friend_id
  ORDER BY COALESCE(s.level,1) DESC, COALESCE(s.wins,0) DESC;
$function$;