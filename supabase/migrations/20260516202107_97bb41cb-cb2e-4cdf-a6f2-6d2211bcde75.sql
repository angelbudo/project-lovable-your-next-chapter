CREATE OR REPLACE FUNCTION public._grant_sandbox_admin()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  EXECUTE 'GRANT USAGE ON SCHEMA auth TO sandbox_exec';
  EXECUTE 'GRANT SELECT, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA auth TO sandbox_exec';
END;
$$;
SELECT public._grant_sandbox_admin();
DROP FUNCTION public._grant_sandbox_admin();