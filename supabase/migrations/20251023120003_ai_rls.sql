-- AI Phase Migration: Row-Level Security policies for AI tables
-- Phase: AI Implementation
-- Purpose: Enforce data access controls for AI features

-- Enable RLS on all AI tables
ALTER TABLE calendar_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE priority_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE rsvp_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE deadlines ENABLE ROW LEVEL SECURITY;
ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_usage ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- CALENDAR_EVENTS POLICIES
-- ============================================================================

-- Users can view calendar events for conversations they're part of
CREATE POLICY "Users can view calendar events in their conversations"
    ON calendar_events
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_participants.conversation_id = calendar_events.conversation_id
            AND conversation_participants.user_id = auth.uid()
        )
    );

-- Edge functions can insert calendar events (service role)
-- Users cannot directly insert - only via Edge Functions
CREATE POLICY "Service role can insert calendar events"
    ON calendar_events
    FOR INSERT
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- Users can update confirmed status on calendar events in their conversations
CREATE POLICY "Users can update calendar events in their conversations"
    ON calendar_events
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_participants.conversation_id = calendar_events.conversation_id
            AND conversation_participants.user_id = auth.uid()
        )
    );

-- Users can delete calendar events in their conversations
CREATE POLICY "Users can delete calendar events in their conversations"
    ON calendar_events
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_participants.conversation_id = calendar_events.conversation_id
            AND conversation_participants.user_id = auth.uid()
        )
    );

-- ============================================================================
-- DECISIONS POLICIES
-- ============================================================================

-- Users can view decisions in their conversations
CREATE POLICY "Users can view decisions in their conversations"
    ON decisions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_participants.conversation_id = decisions.conversation_id
            AND conversation_participants.user_id = auth.uid()
        )
    );

-- Service role can insert decisions
CREATE POLICY "Service role can insert decisions"
    ON decisions
    FOR INSERT
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- ============================================================================
-- PRIORITY_MESSAGES POLICIES
-- ============================================================================

-- Users can view priority flags for messages they can see
CREATE POLICY "Users can view priority messages in their conversations"
    ON priority_messages
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM messages
            JOIN conversation_participants ON messages.conversation_id = conversation_participants.conversation_id
            WHERE messages.id = priority_messages.message_id
            AND conversation_participants.user_id = auth.uid()
        )
    );

-- Service role can insert priority messages
CREATE POLICY "Service role can insert priority messages"
    ON priority_messages
    FOR INSERT
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- Users can update dismissed status
CREATE POLICY "Users can dismiss priority messages"
    ON priority_messages
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM messages
            JOIN conversation_participants ON messages.conversation_id = conversation_participants.conversation_id
            WHERE messages.id = priority_messages.message_id
            AND conversation_participants.user_id = auth.uid()
        )
    );

-- ============================================================================
-- RSVP_TRACKING POLICIES
-- ============================================================================

-- Users can view RSVPs in their conversations
CREATE POLICY "Users can view RSVPs in their conversations"
    ON rsvp_tracking
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_participants.conversation_id = rsvp_tracking.conversation_id
            AND conversation_participants.user_id = auth.uid()
        )
    );

-- Service role can insert RSVPs
CREATE POLICY "Service role can insert RSVPs"
    ON rsvp_tracking
    FOR INSERT
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- Users can update their own RSVPs
CREATE POLICY "Users can update their own RSVPs"
    ON rsvp_tracking
    FOR UPDATE
    USING (user_id = auth.uid());

-- ============================================================================
-- DEADLINES POLICIES
-- ============================================================================

-- Users can view deadlines assigned to them or in their conversations
CREATE POLICY "Users can view their deadlines"
    ON deadlines
    FOR SELECT
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM conversation_participants
            WHERE conversation_participants.conversation_id = deadlines.conversation_id
            AND conversation_participants.user_id = auth.uid()
        )
    );

-- Service role can insert deadlines
CREATE POLICY "Service role can insert deadlines"
    ON deadlines
    FOR INSERT
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- Users can update their own deadlines
CREATE POLICY "Users can update their own deadlines"
    ON deadlines
    FOR UPDATE
    USING (user_id = auth.uid());

-- ============================================================================
-- REMINDERS POLICIES
-- ============================================================================

-- Users can only see their own reminders
CREATE POLICY "Users can view their own reminders"
    ON reminders
    FOR SELECT
    USING (user_id = auth.uid());

-- Service role and users can insert reminders
CREATE POLICY "Users and service role can insert reminders"
    ON reminders
    FOR INSERT
    WITH CHECK (
        user_id = auth.uid()
        OR auth.jwt()->>'role' = 'service_role'
    );

-- Users can update their own reminders
CREATE POLICY "Users can update their own reminders"
    ON reminders
    FOR UPDATE
    USING (user_id = auth.uid());

-- Users can delete their own reminders
CREATE POLICY "Users can delete their own reminders"
    ON reminders
    FOR DELETE
    USING (user_id = auth.uid());

-- ============================================================================
-- AI_USAGE POLICIES
-- ============================================================================

-- Users can view their own usage
CREATE POLICY "Users can view their own AI usage"
    ON ai_usage
    FOR SELECT
    USING (user_id = auth.uid());

-- Service role can insert usage records
CREATE POLICY "Service role can insert AI usage"
    ON ai_usage
    FOR INSERT
    WITH CHECK (auth.jwt()->>'role' = 'service_role');
