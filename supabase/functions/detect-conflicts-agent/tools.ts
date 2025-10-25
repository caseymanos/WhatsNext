import { tool } from '../_shared/deps.ts';
import { z } from '../_shared/deps.ts';

/**
 * Tool definitions for conflict detection agent
 * These tools enable the AI to analyze schedules and detect various types of conflicts
 */

export const conflictDetectionTools = {
  getCalendarEvents: tool({
    description: 'Fetch calendar events within a date range for conflict analysis',
    parameters: z.object({
      startDate: z.string().describe('Start date (YYYY-MM-DD)'),
      endDate: z.string().describe('End date (YYYY-MM-DD)'),
      includeUnconfirmed: z.boolean().default(true).describe('Include unconfirmed events'),
    }),
    execute: async ({ startDate, endDate, includeUnconfirmed }, context) => {
      let query = context.supabase
        .from('calendar_events')
        .select('*')
        .eq('conversation_id', context.conversationId)
        .gte('date', startDate)
        .lte('date', endDate)
        .order('date', { ascending: true })
        .order('time', { ascending: true, nullsFirst: false });

      if (!includeUnconfirmed) {
        query = query.eq('confirmed', true);
      }

      const { data, error } = await query;

      if (error) throw error;

      return {
        events: data || [],
        count: data?.length || 0,
      };
    },
  }),

  getDeadlines: tool({
    description: 'Fetch pending deadlines within a date range',
    parameters: z.object({
      startDate: z.string().describe('Start date (ISO 8601)'),
      endDate: z.string().describe('End date (ISO 8601)'),
      includeLowPriority: z.boolean().default(false),
    }),
    execute: async ({ startDate, endDate, includeLowPriority }, context) => {
      let query = context.supabase
        .from('deadlines')
        .select('*')
        .eq('user_id', context.userId)
        .eq('status', 'pending')
        .gte('deadline', startDate)
        .lte('deadline', endDate)
        .order('deadline', { ascending: true });

      if (!includeLowPriority) {
        query = query.in('priority', ['urgent', 'high', 'medium']);
      }

      const { data, error } = await query;

      if (error) throw error;

      return {
        deadlines: data || [],
        count: data?.length || 0,
      };
    },
  }),

  analyzeTimeConflict: tool({
    description: 'Analyze if two events have a time conflict, considering duration and travel time',
    parameters: z.object({
      event1: z.object({
        id: z.string().optional(),
        title: z.string(),
        date: z.string(),
        time: z.string().nullable(),
        location: z.string().nullable(),
        category: z.string().optional(),
      }),
      event2: z.object({
        id: z.string().optional(),
        title: z.string(),
        date: z.string(),
        time: z.string().nullable(),
        location: z.string().nullable(),
        category: z.string().optional(),
      }),
      travelTimeMinutes: z.number().default(30).describe('Estimated travel time between locations'),
      durationMinutes: z.number().default(60).describe('Assumed duration for each event in minutes'),
    }),
    execute: async ({ event1, event2, travelTimeMinutes, durationMinutes }) => {
      // Different dates = no conflict
      if (event1.date !== event2.date) {
        return {
          conflict: false,
          reason: 'Events on different dates'
        };
      }

      // If either missing time, flag as potential conflict (low severity)
      if (!event1.time || !event2.time) {
        return {
          conflict: true,
          severity: 'low',
          conflictType: 'time_unclear',
          reason: `Multiple events on ${event1.date}, times unclear`,
          description: `Both "${event1.title}" and "${event2.title}" are scheduled for the same day, but one or both are missing specific times`,
          suggestion: 'Verify exact timing to prevent overlap',
          affectedItems: [event1.title, event2.title],
        };
      }

      // Parse times (HH:MM -> minutes since midnight)
      const parseTime = (timeStr: string): number => {
        const [hours, minutes] = timeStr.split(':').map(Number);
        return hours * 60 + minutes;
      };

      const start1 = parseTime(event1.time);
      const end1 = start1 + durationMinutes;

      const start2 = parseTime(event2.time);
      const end2 = start2 + durationMinutes;

      // Check for direct overlap
      if (start1 < end2 && start2 < end1) {
        return {
          conflict: true,
          severity: 'urgent',
          conflictType: 'time_overlap',
          reason: 'Events overlap directly',
          description: `"${event1.title}" (${event1.time}) and "${event2.title}" (${event2.time}) overlap on ${event1.date}`,
          suggestion: 'One event must be rescheduled',
          affectedItems: [event1.title, event2.title],
        };
      }

      // Check for insufficient buffer (considering travel time if different locations)
      const needsTravelTime = event1.location && event2.location &&
                               event1.location !== event2.location;

      const requiredBuffer = needsTravelTime ? travelTimeMinutes : 0;
      const actualBuffer = start2 > end1 ? start2 - end1 : end2 - start1;

      if (actualBuffer < requiredBuffer) {
        const shortage = requiredBuffer - actualBuffer;
        return {
          conflict: true,
          severity: shortage > 30 ? 'high' : 'medium',
          conflictType: 'travel_time',
          reason: 'Insufficient time for travel between locations',
          description: `Only ${actualBuffer}min between "${event1.title}" and "${event2.title}", need ${requiredBuffer}min for travel from ${event1.location} to ${event2.location}`,
          suggestion: `Reschedule to add ${shortage}min buffer, or find alternative transportation`,
          affectedItems: [event1.title, event2.title],
        };
      }

      // Check for back-to-back (same location, no buffer)
      if (actualBuffer === 0 && !needsTravelTime) {
        return {
          conflict: true,
          severity: 'low',
          conflictType: 'no_buffer',
          reason: 'Back-to-back events with no break',
          description: `"${event1.title}" ends exactly when "${event2.title}" starts (${event2.time})`,
          suggestion: 'Consider adding 15min buffer for transitions',
          affectedItems: [event1.title, event2.title],
        };
      }

      return { conflict: false };
    },
  }),

  checkDeadlineConflict: tool({
    description: 'Check if calendar commitments prevent meeting a deadline',
    parameters: z.object({
      deadline: z.object({
        id: z.string().optional(),
        task: z.string(),
        deadline: z.string(),
        priority: z.string(),
        estimatedHours: z.number().default(2).describe('Hours needed to complete task'),
      }),
      events: z.array(z.object({
        title: z.string(),
        date: z.string(),
        time: z.string().nullable(),
      })),
    }),
    execute: async ({ deadline, events }) => {
      const deadlineDate = new Date(deadline.deadline);
      const now = new Date();

      // Calculate hours until deadline
      const hoursRemaining = (deadlineDate.getTime() - now.getTime()) / (1000 * 60 * 60);

      if (hoursRemaining < 0) {
        return {
          conflict: true,
          severity: 'urgent',
          conflictType: 'deadline_passed',
          reason: 'Deadline has already passed',
          description: `${deadline.task} was due ${Math.abs(Math.floor(hoursRemaining))}h ago`,
          suggestion: 'Contact requester to request extension or explain delay',
          affectedItems: [deadline.task],
        };
      }

      // Filter events between now and deadline
      const relevantEvents = events.filter(e => {
        const eventDate = new Date(e.date);
        return eventDate >= now && eventDate <= deadlineDate;
      });

      // Estimate committed hours (assume avg event is 1.5h including prep/travel)
      const committedHours = relevantEvents.length * 1.5;

      // Calculate available working hours (assume 8h/day, excluding weekends for simplicity)
      const daysRemaining = Math.ceil(hoursRemaining / 24);
      const workingDays = Math.max(1, Math.floor(daysRemaining * 5/7)); // Rough weekday estimate
      const theoreticalHours = workingDays * 8;

      const availableHours = theoreticalHours - committedHours;

      if (availableHours < deadline.estimatedHours) {
        const shortage = deadline.estimatedHours - availableHours;
        return {
          conflict: true,
          severity: deadline.priority === 'urgent' || shortage > 4 ? 'urgent' : 'high',
          conflictType: 'deadline_pressure',
          reason: 'Insufficient time available before deadline',
          description: `"${deadline.task}" needs ${deadline.estimatedHours}h but only ${availableHours.toFixed(1)}h available before ${deadlineDate.toLocaleDateString()} (${relevantEvents.length} events scheduled)`,
          suggestion: shortage > deadline.estimatedHours / 2
            ? 'Request deadline extension or cancel/reschedule lower-priority events'
            : 'Prioritize this task, minimize distractions, consider working evenings',
          affectedItems: [deadline.task, ...relevantEvents.slice(0, 3).map(e => e.title)],
        };
      }

      // Warn if cutting it close
      if (availableHours < deadline.estimatedHours * 1.5) {
        return {
          conflict: true,
          severity: 'medium',
          conflictType: 'deadline_tight',
          reason: 'Deadline is achievable but schedule is tight',
          description: `"${deadline.task}" has ${availableHours.toFixed(1)}h available for ${deadline.estimatedHours}h task (little buffer)`,
          suggestion: 'Block focus time ASAP to avoid last-minute rush',
          affectedItems: [deadline.task],
        };
      }

      return { conflict: false };
    },
  }),

  analyzeCapacity: tool({
    description: 'Analyze overall schedule capacity and identify overload periods',
    parameters: z.object({
      events: z.array(z.object({
        title: z.string(),
        date: z.string(),
        time: z.string().nullable(),
        category: z.string().nullable(),
      })),
      daysAhead: z.number().default(7),
    }),
    execute: async ({ events, daysAhead }) => {
      // Group events by date
      const eventsByDate = events.reduce((acc: any, event) => {
        if (!acc[event.date]) acc[event.date] = [];
        acc[event.date].push(event);
        return acc;
      }, {});

      const conflicts: any[] = [];

      // Check for overload patterns
      for (const [date, dateEvents] of Object.entries(eventsByDate)) {
        const eventsArray = dateEvents as any[];

        // More than 4 events in a day = overload
        if (eventsArray.length > 4) {
          conflicts.push({
            conflict: true,
            severity: 'high',
            conflictType: 'capacity',
            reason: 'Too many events in one day',
            description: `${eventsArray.length} events scheduled on ${date}`,
            suggestion: 'Consider rescheduling non-urgent events to spread load',
            affectedItems: eventsArray.map(e => e.title),
          });
        }
        // 3-4 events = caution
        else if (eventsArray.length >= 3) {
          conflicts.push({
            conflict: true,
            severity: 'low',
            conflictType: 'capacity',
            reason: 'Heavy schedule day',
            description: `${eventsArray.length} events on ${date}, minimal downtime`,
            suggestion: 'Ensure time for meals and transitions',
            affectedItems: eventsArray.map(e => e.title),
          });
        }
      }

      // Check for consecutive busy days
      const dates = Object.keys(eventsByDate).sort();
      let consecutiveBusyDays = 0;
      let busyStreak: string[] = [];

      for (const date of dates) {
        if ((eventsByDate[date] as any[]).length >= 2) {
          consecutiveBusyDays++;
          busyStreak.push(date);
        } else {
          if (consecutiveBusyDays >= 3) {
            conflicts.push({
              conflict: true,
              severity: 'medium',
              conflictType: 'capacity',
              reason: 'Extended period without recovery time',
              description: `${consecutiveBusyDays} consecutive busy days (${busyStreak[0]} to ${busyStreak[busyStreak.length - 1]})`,
              suggestion: 'Schedule lighter day or rest period after this stretch',
              affectedItems: [],
            });
          }
          consecutiveBusyDays = 0;
          busyStreak = [];
        }
      }

      return {
        capacityConflicts: conflicts,
        stats: {
          totalEvents: events.length,
          avgEventsPerDay: events.length / daysAhead,
          busiestDay: Object.entries(eventsByDate).sort((a, b) =>
            (b[1] as any[]).length - (a[1] as any[]).length
          )[0],
        },
      };
    },
  }),

  storeConflict: tool({
    description: 'Store a detected conflict in the database for tracking and resolution',
    parameters: z.object({
      conflictType: z.enum(['time_overlap', 'deadline_pressure', 'travel_time', 'capacity', 'time_unclear', 'no_buffer', 'deadline_tight']),
      severity: z.enum(['urgent', 'high', 'medium', 'low']),
      description: z.string(),
      affectedItems: z.array(z.string()),
      suggestedResolution: z.string(),
    }),
    execute: async (params, context) => {
      const serviceClient = context.serviceClient;

      const { data, error } = await serviceClient
        .from('scheduling_conflicts')
        .insert({
          conversation_id: context.conversationId,
          user_id: context.userId,
          conflict_type: params.conflictType,
          severity: params.severity,
          description: params.description,
          affected_items: params.affectedItems,
          suggested_resolution: params.suggestedResolution,
          status: 'unresolved',
        })
        .select()
        .single();

      if (error) throw error;

      return {
        success: true,
        conflictId: data.id,
        message: 'Conflict stored successfully',
      };
    },
  }),

  createReminder: tool({
    description: 'Create a reminder for the user to address a conflict or follow up',
    parameters: z.object({
      title: z.string(),
      reminderTime: z.string().describe('When to remind (ISO 8601)'),
      priority: z.enum(['urgent', 'high', 'medium', 'low']),
      context: z.string().optional().describe('Additional context for the reminder'),
    }),
    execute: async (params, context) => {
      const serviceClient = context.serviceClient;

      const { error } = await serviceClient
        .from('reminders')
        .insert({
          user_id: context.userId,
          title: params.title,
          reminder_time: params.reminderTime,
          priority: params.priority,
          status: 'pending',
          created_by: 'ai',
        });

      if (error) throw error;

      return {
        success: true,
        message: `Reminder created for ${new Date(params.reminderTime).toLocaleString()}`,
      };
    },
  }),

  getUserPreferences: tool({
    description: 'Get user scheduling preferences and learned patterns',
    parameters: z.object({}),
    execute: async (params, context) => {
      const { data } = await context.supabase
        .from('user_preferences')
        .select('*')
        .eq('user_id', context.userId)
        .single();

      return {
        preferences: data || {
          conflict_sensitivity: 'medium',
          travel_time_buffer_minutes: 30,
          work_hours_start: '09:00',
          work_hours_end: '17:00',
        },
      };
    },
  }),
};
