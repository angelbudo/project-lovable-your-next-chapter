DO $$
BEGIN
  RAISE NOTICE 'role: %, session: %', current_user, session_user;
  RAISE NOTICE 'auth owner: %', (SELECT nspowner::regrole FROM pg_namespace WHERE nspname='auth');
  RAISE NOTICE 'can grant auth: %', has_schema_privilege(current_user, 'auth', 'USAGE WITH GRANT OPTION');
END $$;