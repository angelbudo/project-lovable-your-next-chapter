CREATE OR REPLACE FUNCTION public.__apply_admin_sql_lax(sql text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  EXECUTE sql;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE || ': ' || SQLERRM;
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.__apply_admin_sql_lax(text) TO anon, authenticated, service_role;