-- Migration: 20251025120001_message_photos_bucket.sql
-- Description: Add message-photos storage bucket with RLS policies

-- ============================================
-- Create message-photos storage bucket
-- ============================================

-- Create storage bucket (public read access)
INSERT INTO storage.buckets (id, name, public)
VALUES ('message-photos', 'message-photos', true)
ON CONFLICT (id) DO NOTHING;

-- ============================================
-- RLS Policies for message-photos bucket
-- ============================================

-- Public read access to all message photos
CREATE POLICY "Message photos are publicly accessible"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'message-photos');

-- Authenticated users can upload message photos
CREATE POLICY "Authenticated users can upload message photos"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'message-photos' AND
    auth.role() = 'authenticated'
  );

-- Users can delete their own message photos
CREATE POLICY "Users can delete their own message photos"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'message-photos' AND
    auth.role() = 'authenticated'
  );
