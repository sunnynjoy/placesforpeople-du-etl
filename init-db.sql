-- Create database
CREATE DATABASE du_chapters;

-- Connect to the new database
\c du_chapters

-- Create user if not exists
DO $$ BEGIN
  CREATE USER du_user WITH PASSWORD 'changeme';
EXCEPTION WHEN DUPLICATE_OBJECT THEN
  NULL;
END $$;

-- Grant permissions on schema
GRANT USAGE ON SCHEMA public TO du_user;
GRANT CREATE ON SCHEMA public TO du_user;

-- Grant permissions on all tables
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO du_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO du_user;

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO du_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO du_user;