-- Disable RLS on app_settings table
-- This table is for internal system configuration only, not user data
-- The trigger function needs to read these values to work properly

ALTER TABLE app_settings DISABLE ROW LEVEL SECURITY;

COMMENT ON TABLE app_settings IS 'Internal system configuration (RLS disabled for trigger access)';
