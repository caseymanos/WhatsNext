-- Scheduling Conflicts Migration
-- Adds tables for proactive conflict detection and resolution tracking

-- ============================================================================
-- Scheduling Conflicts Table
-- ============================================================================
-- Stores detected scheduling conflicts between events, deadlines, and capacity issues
CREATE TABLE IF NOT EXISTS scheduling_conflicts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Conflict details
    conflict_type TEXT NOT NULL CHECK (conflict_type IN (
        'time_overlap',
        'deadline_pressure',
        'travel_time',
        'capacity',
        'time_unclear',
        'no_buffer',
        'deadline_tight',
        'deadline_passed'
    )),
    severity TEXT NOT NULL CHECK (severity IN ('urgent', 'high', 'medium', 'low')),
    description TEXT NOT NULL,
    affected_items TEXT[] NOT NULL,  -- Event titles, deadline tasks involved

    -- Resolution tracking
    suggested_resolution TEXT NOT NULL,
    status TEXT DEFAULT 'unresolved' CHECK (status IN ('unresolved', 'resolved', 'dismissed')),
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT,
    resolution_strategy TEXT,  -- Which strategy was chosen (reschedule, delegate, etc.)

    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_scheduling_conflicts_user_status
    ON scheduling_conflicts(user_id, status);
CREATE INDEX IF NOT EXISTS idx_scheduling_conflicts_conversation
    ON scheduling_conflicts(conversation_id);
CREATE INDEX IF NOT EXISTS idx_scheduling_conflicts_severity
    ON scheduling_conflicts(severity) WHERE status = 'unresolved';
CREATE INDEX IF NOT EXISTS idx_scheduling_conflicts_created
    ON scheduling_conflicts(created_at DESC);

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_scheduling_conflicts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS scheduling_conflicts_updated_at_trigger ON scheduling_conflicts;
CREATE TRIGGER scheduling_conflicts_updated_at_trigger
    BEFORE UPDATE ON scheduling_conflicts
    FOR EACH ROW
    EXECUTE FUNCTION update_scheduling_conflicts_updated_at();

-- ============================================================================
-- User Preferences Table
-- ============================================================================
-- Stores user scheduling preferences and learned patterns for personalized suggestions
CREATE TABLE IF NOT EXISTS user_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,

    -- Explicit preferences
    priority_hierarchy TEXT[] DEFAULT ARRAY['health', 'education', 'work', 'social'],
    risk_tolerance TEXT DEFAULT 'medium' CHECK (risk_tolerance IN ('low', 'medium', 'high')),
    travel_buffer_minutes INTEGER DEFAULT 30 CHECK (travel_buffer_minutes >= 0 AND travel_buffer_minutes <= 120),
    preferred_delegation JSONB DEFAULT '{}'::jsonb,  -- {"soccer practice": "partner", "grocery shopping": "self"}
    blackout_times JSONB DEFAULT '[]'::jsonb,  -- [{"day": "Monday", "start": "08:00", "end": "09:00"}]

    -- Work schedule
    work_hours_start TIME DEFAULT '09:00',
    work_hours_end TIME DEFAULT '17:00',
    work_days TEXT[] DEFAULT ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],

    -- Learned patterns (updated by AI as it observes user behavior)
    typical_scheduling_patterns JSONB DEFAULT '{}'::jsonb,  -- {"medical": {"days": ["Tuesday"], "times": ["10:00"]}}
    resolution_success_rates JSONB DEFAULT '{}'::jsonb,  -- {"reschedule": 0.85, "delegate": 0.60}

    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Auto-update updated_at timestamp
DROP TRIGGER IF EXISTS user_preferences_updated_at_trigger ON user_preferences;
CREATE TRIGGER user_preferences_updated_at_trigger
    BEFORE UPDATE ON user_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_scheduling_conflicts_updated_at();

-- ============================================================================
-- Resolution Feedback Table
-- ============================================================================
-- Tracks user feedback on conflict resolution suggestions for learning
CREATE TABLE IF NOT EXISTS resolution_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conflict_id UUID REFERENCES scheduling_conflicts(id) ON DELETE CASCADE,

    -- Suggestion details
    suggested_strategy TEXT NOT NULL CHECK (suggested_strategy IN (
        'reschedule',
        'prioritize',
        'delegate',
        'batch',
        'add_buffer',
        'request_extension',
        'other'
    )),

    -- User response
    user_decision TEXT NOT NULL CHECK (user_decision IN ('accepted', 'rejected', 'modified')),
    modification_details TEXT,  -- If modified, what did they change?
    feedback_text TEXT,  -- Optional user comments

    -- Outcome tracking
    was_helpful BOOLEAN,  -- Did this actually solve the problem?

    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_resolution_feedback_user
    ON resolution_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_resolution_feedback_conflict
    ON resolution_feedback(conflict_id);
CREATE INDEX IF NOT EXISTS idx_resolution_feedback_strategy
    ON resolution_feedback(suggested_strategy, user_decision);
CREATE INDEX IF NOT EXISTS idx_resolution_feedback_created
    ON resolution_feedback(created_at DESC);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE scheduling_conflicts ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE resolution_feedback ENABLE ROW LEVEL SECURITY;

-- scheduling_conflicts policies
DROP POLICY IF EXISTS "Users can view their own conflicts" ON scheduling_conflicts;
CREATE POLICY "Users can view their own conflicts" ON scheduling_conflicts FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own conflicts" ON scheduling_conflicts;
CREATE POLICY "Users can insert their own conflicts" ON scheduling_conflicts FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own conflicts" ON scheduling_conflicts;
CREATE POLICY "Users can update their own conflicts" ON scheduling_conflicts FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage all conflicts" ON scheduling_conflicts;
CREATE POLICY "Service role can manage all conflicts" ON scheduling_conflicts FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- user_preferences policies
DROP POLICY IF EXISTS "Users can view their own preferences" ON user_preferences;
CREATE POLICY "Users can view their own preferences" ON user_preferences FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own preferences" ON user_preferences;
CREATE POLICY "Users can insert their own preferences" ON user_preferences FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own preferences" ON user_preferences;
CREATE POLICY "Users can update their own preferences" ON user_preferences FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage all preferences" ON user_preferences;
CREATE POLICY "Service role can manage all preferences" ON user_preferences FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- resolution_feedback policies
DROP POLICY IF EXISTS "Users can view their own feedback" ON resolution_feedback;
CREATE POLICY "Users can view their own feedback" ON resolution_feedback FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own feedback" ON resolution_feedback;
CREATE POLICY "Users can insert their own feedback" ON resolution_feedback FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage all feedback" ON resolution_feedback;
CREATE POLICY "Service role can manage all feedback" ON resolution_feedback FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================================================
-- Comments for documentation
-- ============================================================================

COMMENT ON TABLE scheduling_conflicts IS 'Stores detected scheduling conflicts from AI analysis';
COMMENT ON TABLE user_preferences IS 'User scheduling preferences and learned patterns for personalized conflict resolution';
COMMENT ON TABLE resolution_feedback IS 'Tracks user responses to conflict resolution suggestions for learning and improvement';

COMMENT ON COLUMN scheduling_conflicts.conflict_type IS 'Type of conflict: time_overlap, deadline_pressure, travel_time, capacity, etc.';
COMMENT ON COLUMN scheduling_conflicts.severity IS 'Urgency level: urgent (immediate action), high (within 24h), medium (within week), low (advisory)';
COMMENT ON COLUMN scheduling_conflicts.affected_items IS 'Array of event titles or deadline tasks involved in the conflict';
COMMENT ON COLUMN scheduling_conflicts.suggested_resolution IS 'AI-generated suggestion for resolving the conflict';

COMMENT ON COLUMN user_preferences.priority_hierarchy IS 'Ordered list of life areas by importance (e.g., [health, education, work, social])';
COMMENT ON COLUMN user_preferences.travel_buffer_minutes IS 'Preferred buffer time between events at different locations';
COMMENT ON COLUMN user_preferences.typical_scheduling_patterns IS 'JSONB storing learned patterns like preferred days/times for event categories';

COMMENT ON COLUMN resolution_feedback.user_decision IS 'Whether user accepted, rejected, or modified the AI suggestion';
COMMENT ON COLUMN resolution_feedback.was_helpful IS 'Post-resolution feedback: did the suggestion actually work?';

-- ============================================================================
-- Initial Data
-- ============================================================================

-- Create default preferences for existing users (optional)
-- This will be done on-demand when users first use conflict detection
