CREATE OR REPLACE FUNCTION public.send_friend_request_by_username(p_username text)
RETURNS public.friendships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  uname text := lower(trim(p_username));
  target uuid;
  ua uuid;
  ub uuid;
  result public.friendships;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF uname IS NULL OR length(uname) = 0 THEN RAISE EXCEPTION 'invalid_username'; END IF;
  SELECT user_id INTO target FROM public.profiles WHERE lower(username) = uname;
  IF target IS NULL THEN RAISE EXCEPTION 'user_not_found'; END IF;
  IF target = uid THEN RAISE EXCEPTION 'cannot_friend_self'; END IF;
  IF uid < target THEN ua := uid; ub := target; ELSE ua := target; ub := uid; END IF;
  INSERT INTO public.friendships (user_a, user_b, requested_by, status)
  VALUES (ua, ub, uid, 'pending')
  ON CONFLICT (user_a, user_b) DO UPDATE SET status = CASE
    WHEN public.friendships.status = 'pending' AND public.friendships.requested_by <> EXCLUDED.requested_by THEN 'accepted'
    ELSE public.friendships.status END, updated_at = now()
  RETURNING * INTO result;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_friend_request_by_username(text) TO authenticated;