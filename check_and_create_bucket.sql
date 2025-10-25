-- Check if message-photos bucket exists and create if needed
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'message-photos') THEN
        INSERT INTO storage.buckets (id, name, public)
        VALUES ('message-photos', 'message-photos', true);

        RAISE NOTICE 'Created message-photos bucket';
    ELSE
        RAISE NOTICE 'message-photos bucket already exists';
    END IF;
END $$;

-- Ensure RLS policies exist
DO $$
BEGIN
    -- Drop existing policies if they exist (to avoid conflicts)
    DROP POLICY IF EXISTS "Message photos are publicly accessible" ON storage.objects;
    DROP POLICY IF EXISTS "Authenticated users can upload message photos" ON storage.objects;
    DROP POLICY IF EXISTS "Users can delete their own message photos" ON storage.objects;

    -- Create policies
    CREATE POLICY "Message photos are publicly accessible"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'message-photos');

    CREATE POLICY "Authenticated users can upload message photos"
      ON storage.objects FOR INSERT
      WITH CHECK (
        bucket_id = 'message-photos' AND
        auth.role() = 'authenticated'
      );

    CREATE POLICY "Users can delete their own message photos"
      ON storage.objects FOR DELETE
      USING (
        bucket_id = 'message-photos' AND
        auth.role() = 'authenticated'
      );

    RAISE NOTICE 'RLS policies created successfully';
END $$;
