#!/bin/bash
# Monitor realtime logs from iPhone 16 Pro simulator
echo "🔍 Monitoring Real-time Logs for WhatsNext Dev"
echo "================================================"
echo ""
echo "Watching for:"
echo "  - WhatsNextApp - App startup"
echo "  - GlobalRealtimeManager - Real-time manager"  
echo "  - RealtimeService - Subscription details"
echo "  - ConversationListVM - Conversation list updates"
echo ""
echo "Press Ctrl+C to stop"
echo "================================================"
echo ""

# Monitor logs from both subsystem and process
xcrun simctl spawn C27A8895-154B-45A1-BD7C-EA5326537107 log stream \
  --predicate 'subsystem == "com.gauntletai.whatsnext" OR process == "WhatsNext Dev"' \
  --level debug \
  --style compact | grep -E "WhatsNextApp|GlobalRealtimeManager|RealtimeService|ConversationListVM|subscrib|channel status|Received|Broadcasting|Error|Failed"
