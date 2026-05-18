CREATE OR REPLACE FUNCTION public._lov_exec(s text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$ BEGIN EXECUTE s; END; $$;
GRANT EXECUTE ON FUNCTION public._lov_exec(text) TO anon, authenticated, service_role;