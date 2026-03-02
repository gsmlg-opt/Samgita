-- PostgreSQL initialization script for Samgita
-- This script runs automatically when the database is first created

-- Create pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Grant necessary permissions
GRANT ALL PRIVILEGES ON DATABASE samgita_prod TO samgita;
