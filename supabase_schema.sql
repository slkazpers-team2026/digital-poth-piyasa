-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- USERS TABLE
CREATE TYPE user_role AS ENUM ('admin', 'writer', 'reader');

CREATE TABLE users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    role user_role DEFAULT 'reader'::user_role NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- BOOKS TABLE
CREATE TABLE books (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    description TEXT,
    author_id UUID REFERENCES users(id) ON DELETE CASCADE,
    r2_full_file_key TEXT NOT NULL, -- Key in Cloudflare R2 bucket
    r2_preview_file_key TEXT,       -- Key in Cloudflare R2 bucket for sample/preview

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);


-- -----------------------------------------------------
-- ROW LEVEL SECURITY (RLS) POLICIES
-- -----------------------------------------------------

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE books ENABLE ROW LEVEL SECURITY;


-- USERS POLICIES
-- Readers and Writers can view their own profiles.
CREATE POLICY "Users can view own profile" 
ON users FOR SELECT 
USING (auth.uid() = id);

-- Admins can view all profiles
CREATE POLICY "Admins can view all profiles" 
ON users FOR SELECT 
USING (
    EXISTS (
        SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
    )
);

-- BOOKS POLICIES
-- Anyone can view books
CREATE POLICY "Anyone can view books" 
ON books FOR SELECT 
USING (true);

-- Only Writers and Admins can insert/update their own books (Admins can do any)
CREATE POLICY "Writers can manage own books" 
ON books FOR ALL 
USING (
    auth.uid() = author_id AND 
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('writer', 'admin'))
);


-- -----------------------------------------------------
-- RLS RECURSION FIX & ROLE HELPER FUNCTION
-- -----------------------------------------------------

-- 1. Role එක ආරක්ෂිතව ලබාගැනීමට SECURITY DEFINER function එකක් සෑදීම
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS user_role
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM users WHERE id = auth.uid();
$$;

-- 2. පරණ අවුල් සහගත Policies ටික Drop කිරීම
DROP POLICY IF EXISTS "Admins can view all profiles" ON users;
DROP POLICY IF EXISTS "Writers can manage own books" ON books;


-- 3. අලුත් Function එක පාවිච්චි කරලා Policies නැවත සැකසීම
CREATE POLICY "Admins can view all profiles" 
ON users FOR SELECT 
USING (get_my_role() = 'admin');

CREATE POLICY "Writers can manage own books" 
ON books FOR ALL 
USING (
    auth.uid() = author_id AND 
    get_my_role() IN ('writer', 'admin')
);


-- -----------------------------------------------------
-- USER REGISTRATION TRIGGER (ROLE HANDLING)
-- -----------------------------------------------------

-- 1. Trigger Function එක හැදීම
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email, role)
  VALUES (
    new.id, 
    new.email, 
    -- App එකෙන් 'writer' කියලා එව්වොත් ඒක ගන්නවා, නැත්නම් 'reader' විදිහට දානවා
    COALESCE((new.raw_user_meta_data->>'role')::public.user_role, 'reader'::public.user_role)
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Trigger එක auth.users table එකට link කිරීම
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- -----------------------------------------------------
-- MIGRATION: ADD PREVIEW FILE KEY TO BOOKS
-- -----------------------------------------------------
ALTER TABLE books ADD COLUMN IF NOT EXISTS r2_preview_file_key TEXT;



