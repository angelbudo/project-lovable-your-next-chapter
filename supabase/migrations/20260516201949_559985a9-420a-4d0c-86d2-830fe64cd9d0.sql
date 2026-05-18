CREATE TABLE IF NOT EXISTS public._tmp_realtime_test (id int);
ALTER TABLE public._tmp_realtime_test ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public._tmp_realtime_test; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DROP TABLE public._tmp_realtime_test;