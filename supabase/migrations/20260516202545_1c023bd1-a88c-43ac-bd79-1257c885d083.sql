CREATE OR REPLACE FUNCTION public.__apply_admin_sql(sql text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  -- Become sandbox_exec (table owner) so ALTER PUBLICATION / DDL on those tables works
  SET LOCAL ROLE sandbox_exec;
  EXECUTE sql;
END;
$fn$;