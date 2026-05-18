DO $$
DECLARE r text;
BEGIN
  SELECT current_user INTO r;
  RAISE NOTICE 'migration runs as: %', r;
END $$;