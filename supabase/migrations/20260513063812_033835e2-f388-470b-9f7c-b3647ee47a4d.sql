CREATE OR REPLACE FUNCTION public.get_public_avatars_by_devices(p_device_ids text[])
RETURNS TABLE (device_id text, avatar_url text, username text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT al.device_id, p.avatar_url, p.username
  FROM public.account_links al
  JOIN public.profiles p ON p.user_id = al.user_id
  WHERE al.device_id = ANY(p_device_ids);
$$;

GRANT EXECUTE ON FUNCTION public.get_public_avatars_by_devices(text[]) TO anon, authenticated;