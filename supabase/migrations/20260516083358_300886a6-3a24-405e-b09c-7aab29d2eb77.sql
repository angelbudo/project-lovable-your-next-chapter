DO $$
DECLARE
  rec RECORD;
  new_uid uuid;
BEGIN
  FOR rec IN
    SELECT * FROM (VALUES
      ('martacarbo',  'Marta Carbó',     'martacarbo.demo@truc.local',  12, 7200,  48, 22, 3,  0, 9),
      ('jordipuig',   'Jordi Puig',      'jordipuig.demo@truc.local',    8, 3100,  25, 30, 5,  0, 6),
      ('nuriaroca',   'Núria Roca',      'nuriaroca.demo@truc.local',   15, 11500, 80, 35, 1,  2, 12),
      ('pauferrer',   'Pau Ferrer',      'pauferrer.demo@truc.local',    5, 1200,  10, 15, 8,  0, 4),
      ('laiavidal',   'Laia Vidal',      'laiavidal.demo@truc.local',   20, 21000, 120, 60, 2, 0, 18),
      ('ericmoreno',  'Eric Moreno',     'ericmoreno.demo@truc.local',   3,  450,   4,  8, 4,  0, 2),
      ('cristinasol', 'Cristina Solé',   'cristinasol.demo@truc.local', 10, 5400,  35, 28, 6,  1, 7)
    ) AS t(uname, dname, mail, lvl, xp, wins, losses, abandoned, cstreak, mstreak)
  LOOP
    new_uid := gen_random_uuid();

    INSERT INTO auth.users (
      id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
    ) VALUES (
      new_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', rec.mail,
      crypt(gen_random_uuid()::text, gen_salt('bf')), now(),
      jsonb_build_object('provider','email','providers',ARRAY['email']),
      jsonb_build_object('display_name', rec.dname),
      now(), now(), '', '', '', ''
    );

    -- Trigger crea profile + user_stats. Ahora actualizamos.
    UPDATE public.profiles
      SET username = rec.uname, display_name = rec.dname
      WHERE user_id = new_uid;

    UPDATE public.user_stats
      SET level = rec.lvl, xp = rec.xp, wins = rec.wins, losses = rec.losses,
          abandoned = rec.abandoned, current_streak = rec.cstreak, max_streak = rec.mstreak
      WHERE user_id = new_uid;
  END LOOP;
END $$;