-- Apply remaining migrations: account_deletion, sala_chat, room_chat_flags, admin_passwords, chat_flag_audit, profiles, user_stats, friendships, RPCs
-- All migration files are idempotent (use IF NOT EXISTS / DO blocks)

-- Read content from /tmp/all_migrations.sql via inline copy
-- (See migration files in supabase/migrations/)
SELECT 1;