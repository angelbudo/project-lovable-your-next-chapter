DO $$
DECLARE
  ids text[] := ARRAY[
    '9e962701-3996-4da1-951e-d90565959e40',
    '5bf5a31e-c4dc-4312-a81b-cfe8d8c5a534',
    '9e1015d4-1521-4ecb-8f62-a4041177dbef',
    '6ef4f835-c72c-4766-a85b-d4a3e2c3b865',
    'a28dd10d-3efe-4dc7-a6c4-a85e24bb748d',
    'd208c1aa-2f7a-428c-80e1-daee818c2553',
    '2fac2a3d-1263-4984-9d6d-95253d1cbe3e',
    '39202db6-c5a7-440f-8238-d4c9a05c8854',
    '11111111-1111-1111-1111-111111111101',
    '11111111-1111-1111-1111-111111111102',
    '11111111-1111-1111-1111-111111111103',
    '11111111-1111-1111-1111-111111111104',
    '11111111-1111-1111-1111-111111111105'
  ];
  names text[] := ARRAY[
    'Maria Trucàs','Joan Manilla','Laia Envit','Pau Espases','Núria Bastos',
    'Marc Oros','Carla Copes','Toni Set','Ferran Rei','Laura As',
    'Jordi Sota','Anna Cavall','Quim Mà'
  ];
  unames text[] := ARRAY[
    'maria_trucas','joan_manilla','laia_envit','pau_espases','nuria_bastos',
    'marc_oros','carla_copes','toni_set','ferran_rei','laura_as',
    'jordi_sota','anna_cavall','quim_ma'
  ];
  i int;
BEGIN
  FOR i IN 1..array_length(ids,1) LOOP
    INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_sso_user)
    VALUES (ids[i]::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', unames[i] || '@mock.local', '', now(), now(), now(), '{"provider":"email"}'::jsonb, jsonb_build_object('display_name', names[i]), false)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profiles (user_id, username, display_name, friend_code, email)
    VALUES (ids[i]::uuid, unames[i], names[i], public.gen_friend_code(), unames[i] || '@mock.local')
    ON CONFLICT (user_id) DO UPDATE SET username = EXCLUDED.username, display_name = EXCLUDED.display_name;

    INSERT INTO public.user_stats (user_id, wins, losses, current_streak, max_streak, xp, level)
    VALUES (ids[i]::uuid, (10 + i*3), (5 + i), (i % 5), (i + 2), (200 + i*150), GREATEST(1, i))
    ON CONFLICT (user_id) DO UPDATE SET wins = EXCLUDED.wins, losses = EXCLUDED.losses, xp = EXCLUDED.xp, level = EXCLUDED.level;
  END LOOP;
END $$;