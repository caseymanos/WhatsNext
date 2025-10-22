MessageAI.pdf
pdf

create an initial PRD from this document. I'd like to use supabase as the backend service over firebase.


Synthesized project requirements and architected Supabase-based PRD framework.




MessageAI - Product Requirements Document (PRD)
I'll create a comprehensive PRD for your messaging app project. Since you're new to this, I'll explain key concepts as we go through each section.

1. Product Vision
What is this? The product vision is your "north star" - it explains what you're building and why it matters.

Vision Statement: Build a production-quality, cross-platform messaging application that combines WhatsApp-level reliability with intelligent AI features that genuinely improve how people communicate.

Success Definition: A messaging app where messages are never lost, delivery is instant, offline scenarios are handled gracefully, and AI features solve real user problems rather than being gimmicks.

2. Target User & Persona Selection
Teaching moment: A persona is a fictional but realistic representation of your target user. You'll choose ONE of these to focus your AI features:

For this PRD, let's plan for Remote Team Professional as an example (you can choose differently):

Persona: Remote Team Professional

Who: Software engineers, designers, PMs in distributed teams
Pain Points:
Drowning in message threads
Missing important information
Constant context switching
Time zone coordination challenges
Goals: Stay on top of team communication without being overwhelmed
3. Technical Architecture
Teaching moment: The technical stack is the foundation of your app - these are the tools and services you'll use to build it.

Backend: Supabase
Why Supabase? It's an open-source Firebase alternative that gives you:

PostgreSQL database (more powerful than Firestore)
Real-time subscriptions (for instant message delivery)
Authentication (built-in user management)
Storage (for images/media)
Edge Functions (serverless code for AI calls)
Supabase Services We'll Use:
├── Supabase Auth → User authentication
├── Supabase Database (PostgreSQL) → Message storage
├── Supabase Realtime → Live message sync
├── Supabase Storage → Media files
└── Supabase Edge Functions → AI feature processing
```

### Frontend: React Native + Expo
**Why this choice?**
- Write once, run on both iOS and Android
- Expo simplifies deployment and testing
- Fast development cycle
```
Mobile Stack:
├── React Native → Cross-platform framework
├── Expo → Development tools & deployment
├── Expo SQLite → Local message storage (offline support)
└── Expo Notifications → Push notifications
```

### AI Integration
```
AI Stack:
├── Anthropic Claude API → LLM for AI features
├── Vercel AI SDK → Simplified agent development
└── RAG Pipeline → Context-aware AI using conversation history
4. Core Features - MVP (24 Hours)
Teaching moment: MVP stands for Minimum Viable Product - the bare minimum features needed to prove your app works.

4.1 Authentication
 User registration (email/password)
 User login
 Profile creation (username, display name, profile picture)
 Session management
Database Schema:

sql
-- users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP
);
4.2 One-on-One Chat
 Create conversation between two users
 Send text messages
 Display message history
 Message timestamps
 Message delivery states (sending → sent → delivered → read)
Database Schema:

sql
-- conversations table
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at TIMESTAMP DEFAULT NOW(),
  is_group BOOLEAN DEFAULT FALSE
);

-- conversation_participants table
CREATE TABLE conversation_participants (
  conversation_id UUID REFERENCES conversations(id),
  user_id UUID REFERENCES users(id),
  joined_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (conversation_id, user_id)
);

-- messages table
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id),
  sender_id UUID REFERENCES users(id),
  content TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  status TEXT DEFAULT 'sent', -- sent, delivered, read
  local_id TEXT -- for optimistic UI
);
4.3 Real-Time Messaging
Teaching moment: Real-time means messages appear instantly without refreshing. Supabase Realtime listens for database changes.

 Subscribe to new messages in active conversation
 Receive messages instantly when sent by other users
 Update message status in real-time (delivery, read receipts)
Implementation Pattern:

javascript
// Subscribe to new messages
supabase
  .channel('messages')
  .on('postgres_changes', 
    { event: 'INSERT', schema: 'public', table: 'messages' },
    (payload) => {
      // Add new message to UI
    }
  )
  .subscribe();
4.4 Offline Support & Message Persistence
Teaching moment: Offline support means your app works even without internet, then syncs when connection returns.

 Store messages locally using Expo SQLite
 Queue outgoing messages when offline
 Sync messages when connection restored
 Display offline indicator
Local Database Schema (SQLite):

sql
CREATE TABLE local_messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT,
  sender_id TEXT,
  content TEXT,
  created_at INTEGER,
  status TEXT,
  sync_status TEXT -- pending, synced, failed
);
4.5 Optimistic UI Updates
Teaching moment: Optimistic UI means showing the message immediately (optimistically assuming it will succeed), then updating if it fails.

 Display sent message immediately in UI
 Show "sending" indicator
 Update to "sent" when server confirms
 Handle failures gracefully (retry/show error)
4.6 Presence System
 Track user online/offline status
 Show "last seen" timestamp
 Display "typing" indicator
Database Schema:

sql
-- presence table (or use Supabase Realtime presence)
CREATE TABLE user_presence (
  user_id UUID PRIMARY KEY REFERENCES users(id),
  status TEXT DEFAULT 'offline', -- online, offline, away
  last_seen TIMESTAMP,
  typing_in_conversation UUID
);
4.7 Group Chat
 Create group conversations (3+ users)
 Add/remove participants
 Group name and avatar
 Message attribution (show sender in group)
 Read receipts per user
Database Schema Addition:

sql
-- Add to conversations table
ALTER TABLE conversations ADD COLUMN name TEXT;
ALTER TABLE conversations ADD COLUMN avatar_url TEXT;

-- read_receipts table
CREATE TABLE read_receipts (
  message_id UUID REFERENCES messages(id),
  user_id UUID REFERENCES users(id),
  read_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);
```

### 4.8 Push Notifications
- [ ] Send notification when app is backgrounded
- [ ] Handle foreground notifications
- [ ] Notification for new messages
- [ ] Deep link to conversation from notification

---

## 5. AI Features - Post-MVP

**Teaching moment**: These features use Large Language Models (LLMs) like Claude to add intelligence to your app.

### For Remote Team Professional Persona:

#### 5.1 Required AI Features (All 5)

**1. Thread Summarization**
```
User Action: Long-press on conversation → "Summarize"
AI Task: Generate concise summary of last N messages
Technical: 
- Fetch recent messages from DB
- Send to Claude with summarization prompt
- Display summary in modal
```

**2. Action Item Extraction**
```
User Action: Click "Extract Actions" button
AI Task: Identify tasks, deadlines, assignments from conversation
Technical:
- Use Claude with structured output (JSON)
- Parse: {task, assignee, deadline, status}
- Display as checklist
```

**3. Smart Search**
```
User Action: Search bar with natural language query
AI Task: Semantic search across messages
Technical:
- Store message embeddings in Supabase (pgvector)
- Convert query to embedding
- Find similar messages
- Rank by relevance
```

**4. Priority Message Detection**
```
User Action: Automatic/filter view
AI Task: Identify urgent/important messages
Technical:
- Analyze messages for urgency indicators
- Score: urgent questions, deadlines, @mentions
- Highlight in UI or create "Priority" filter
```

**5. Decision Tracking**
```
User Action: Tag message as decision
AI Task: Extract and track decisions made in conversations
Technical:
- Identify decision statements
- Store in decisions table
- Create timeline view
```

#### 5.2 Advanced AI Capability (Choose 1)

**Option A: Multi-Step Agent**
```
Feature: Autonomous team offsite planner
User: "Plan a team offsite in Austin for 8 people in March"
Agent:
1. Searches for venues
2. Checks team availability
3. Proposes 3 options with pros/cons
4. Handles booking once approved
```

**Option B: Proactive Assistant**
```
Feature: Auto-detect scheduling needs
Example: "Let's meet next week to discuss"
Agent: Analyzes context, suggests 3 meeting times,
       checks calendars, sends calendar invites
6. Database Schema (Complete)
Here's the full Supabase PostgreSQL schema:

sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP,
  status TEXT DEFAULT 'offline'
);

-- Conversations
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT,
  avatar_url TEXT,
  is_group BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Conversation Participants
CREATE TABLE conversation_participants (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMP DEFAULT NOW(),
  last_read_at TIMESTAMP,
  PRIMARY KEY (conversation_id, user_id)
);

-- Messages
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  message_type TEXT DEFAULT 'text', -- text, image, system
  media_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  status TEXT DEFAULT 'sent',
  local_id TEXT,
  edited_at TIMESTAMP,
  deleted_at TIMESTAMP
);

-- Read Receipts
CREATE TABLE read_receipts (
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  read_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);

-- AI Extracted Data
CREATE TABLE action_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id),
  message_id UUID REFERENCES messages(id),
  task TEXT NOT NULL,
  assignee_id UUID REFERENCES users(id),
  deadline TIMESTAMP,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE decisions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id),
  message_id UUID REFERENCES messages(id),
  decision_text TEXT NOT NULL,
  decided_by UUID REFERENCES users(id),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_participants_user ON conversation_participants(user_id);
```

---

## 7. Implementation Timeline

### Day 1 (MVP - 24 hours)
- [ ] Set up Supabase project
- [ ] Create database schema
- [ ] Set up React Native + Expo project
- [ ] Implement authentication (4 hours)
- [ ] Build basic chat UI (4 hours)
- [ ] Implement real-time messaging (6 hours)
- [ ] Add local storage for offline support (4 hours)
- [ ] Basic group chat (4 hours)
- [ ] Push notifications setup (2 hours)

### Days 2-3 (Polish Core Features)
- [ ] Optimistic UI refinements
- [ ] Offline queue with retry logic
- [ ] Presence system
- [ ] Read receipts
- [ ] Media support (images)
- [ ] Message editing/deletion
- [ ] Testing on physical devices

### Days 4-5 (AI Features)
- [ ] Set up Claude API
- [ ] Implement RAG pipeline
- [ ] Build 5 required AI features
- [ ] Test AI features with real conversations

### Days 6-7 (Advanced AI + Polish)
- [ ] Implement chosen advanced AI capability
- [ ] UI/UX polish
- [ ] Performance optimization
- [ ] Deploy to TestFlight/Expo Go
- [ ] Create demo video
- [ ] Write persona brainlift

---

## 8. Key Technical Decisions

### Why Supabase Over Firebase?

| Feature | Supabase | Firebase |
|---------|----------|----------|
| Database | PostgreSQL (relational, SQL) | NoSQL (Firestore) |
| Queries | Complex SQL queries, joins | Limited querying |
| Open Source | Yes (can self-host) | No |
| Pricing | More predictable | Can get expensive |
| Real-time | PostgreSQL CDC | Native |

**For this project**: Supabase is better because:
1. SQL is more intuitive for chat relationships
2. PostgreSQL supports advanced features (full-text search, embeddings with pgvector)
3. More control and transparency
4. Easier to add AI features (RAG with pgvector)

### Message Sync Strategy

**Teaching moment**: You need a strategy for keeping messages in sync between devices and handling offline scenarios.
```
Strategy: Optimistic UI + Background Sync
1. User sends message → Show immediately in UI (optimistic)
2. Store in local SQLite with sync_status: 'pending'
3. Send to Supabase in background
4. On success: Update sync_status: 'synced'
5. On failure: Mark sync_status: 'failed', retry
6. On reconnect: Sync all pending messages
9. Success Criteria
MVP Success (Must Pass)
✅ Two users can send messages in real-time
✅ Messages persist after app restart
✅ Offline messages sync when online
✅ Group chat works with 3+ users
✅ Read receipts show correctly
✅ Push notifications deliver
✅ App handles background/foreground/force-quit
Final Success
✅ All 5 AI features work reliably
✅ Advanced AI feature demonstrates multi-step capability
✅ App feels responsive and polished
✅ Handles edge cases (poor network, rapid messages)
✅ Deployed and testable by others
10. Non-Functional Requirements
Teaching moment: These are the "how well" requirements, not just "what" features.

Performance
Messages appear in < 100ms for online users
App launches in < 2 seconds
Smooth scrolling through message history
Handles 1000+ messages per conversation
Reliability
No message loss (even with crashes)
Offline queue holds 100+ messages
Graceful degradation on slow networks
Security
End-to-end encryption (stretch goal)
API keys stored securely
Row-level security in Supabase
11. Out of Scope (v1)
These features would be great but aren't required for the one-week sprint:

Voice/video calls
End-to-end encryption
Message reactions
Message forwarding
Disappearing messages
Story/status features
Payment integration
Next Steps
Set up development environment
Create Supabase account
Initialize React Native + Expo project
Install dependencies
Start with authentication
Implement sign up/login
Test on one device
Build messaging core
Create basic chat UI
Implement send/receive
Add real-time sync
Would you like me to help you with:

Setting up the Supabase project and database schema?
Creating the initial React Native project structure?
Implementing a specific feature first?
Let me know which direction you'd like to go, and I'll guide you through it step by step!

before we go furhter, why react over swiftui?


Weighed cross-platform benefits against native performance tradeoffs.
10s









Great question! Let me give you an honest comparison so you can make the right choice for your situation.

React Native vs SwiftUI: The Real Trade-offs
SwiftUI Strengths
Native performance - Buttery smooth, no JavaScript bridge
Better iOS integration - Widgets, shortcuts, ShareSheet, etc. work seamlessly
More polished feel - Native animations and interactions
Direct API access - No waiting for React Native library updates
The brief recommends it - "Golden Path: Firebase + Swift"
React Native Strengths
One codebase = two platforms - iOS + Android from single code
Faster initial development - Write once vs. writing twice
Supabase has excellent JS SDK - Better documented, more examples
Easier to find help - Larger community for cross-platform
Hot reload - See changes instantly without rebuilding
The Critical Question: What's Your Goal?
Choose SwiftUI if:
You want the best possible iOS app - Native always wins on quality
You already know Swift - Don't learn a new framework under time pressure
You're targeting iOS users specifically - Your persona uses iPhones
You want to showcase iOS expertise - For a job/portfolio
Choose React Native if:
You want to reach more users - iOS + Android
You're stronger in JavaScript - Play to your strengths
Time is the constraint - One codebase is genuinely faster
You want to learn cross-platform - Valuable skill for startups
My Honest Take for This Project
Given you have 7 days and need to:

Build a complete messaging app
Add 5 AI features + 1 advanced feature
Deploy and create a demo video
I'd actually lean toward SwiftUI if:

You're comfortable with Swift
You're okay with iOS-only for v1
You value quality over reach
Here's why: The project says "cross-platform" in the title, but the requirements allow you to "Choose ONE" platform. A really polished iOS app is better than a mediocre cross-platform app.

But React Native makes sense if:

You're stronger in JavaScript
You want to demo on multiple types of devices (your iPhone + friend's Android)
You're less familiar with native iOS development
What I'd Do
If I were starting today with Supabase:

Day 1 Decision Matrix:

Already know Swift well? → SwiftUI
Already know React/JS well? → React Native
Know both equally? → SwiftUI (higher quality)
Know neither? → React Native (more resources/examples)
The Supabase Factor
One thing that matters: Supabase has fantastic JavaScript support. Their docs, examples, and real-time features are all JS-first. The Swift SDK exists but has fewer examples.

javascript
// Supabase Realtime in JS - extensively documented
const channel = supabase
  .channel('messages')
  .on('postgres_changes', {...})
  .subscribe()
vs

swift
// Supabase Realtime in Swift - less documented
let channel = supabase.channel("messages")
  .on(.postgresChanges(...)) { ... }
  .subscribe()
Both work, but you'll find 10x more examples for JavaScript.

My Recommendation
For this specific project with Supabase: I'd go React Native + Expo

Here's why:

7 days is tight - You need velocity over perfection
Supabase + JS is well-trodden - More examples, easier debugging
You can test on both platforms - Richer demo video
The AI SDK (Vercel) is JS-first - Better integration
Expo simplifies deployment - TestFlight is great, but Expo Go is instant
But if you tell me "I'm a senior iOS dev" → then absolutely SwiftUI.

Want Me to Switch the PRD?
I can completely rewrite the PRD for SwiftUI + Supabase if that's your preference. Just tell me:

Your comfort level: Swift vs JavaScript/React?
Your priority: Single platform quality vs multi-platform reach?
Your goal: Portfolio piece vs actually launching something?
What's your background? That'll help me give you the right recommendation.

yes, switch to swiftui


Pivoted technical stack from React Native to SwiftUI comprehensively.



MessageAI - Product Requirements Document (PRD)
SwiftUI + Supabase Edition
Perfect choice! SwiftUI will give you the best possible iOS experience. Let me rebuild this PRD for native iOS development.

1. Product Vision
Vision Statement: Build a production-quality iOS messaging application that combines WhatsApp-level reliability with intelligent AI features that genuinely improve how people communicate.

Success Definition: A native iOS messaging app where messages are never lost, delivery is instant, offline scenarios are handled gracefully, and AI features solve real user problems.

2. Target User & Persona Selection
Persona: Remote Team Professional (you can choose differently)

Who: Software engineers, designers, PMs in distributed teams
Pain Points:
Drowning in message threads
Missing important information
Constant context switching
Time zone coordination challenges
Device: iPhone (iOS 16+)
3. Technical Architecture
Teaching moment: We're building a native iOS app. This means writing Swift code that talks directly to iOS frameworks - no JavaScript bridge, maximum performance.

Backend: Supabase
Supabase Services:
├── Supabase Auth → User authentication
├── PostgreSQL Database → Message storage
├── Realtime → Live message sync
├── Storage → Media files (images)
└── Edge Functions → AI processing
```

### Frontend: SwiftUI + Swift Concurrency
**Teaching moment**: SwiftUI is Apple's modern UI framework. It's declarative (you describe what you want) vs imperative (step-by-step instructions).
```
iOS Native Stack:
├── SwiftUI → UI framework
├── Swift Concurrency (async/await) → Modern async programming
├── SwiftData → Local storage (iOS 17+) or Core Data (iOS 16)
├── URLSession → Networking
├── Combine → Reactive programming for real-time updates
└── APNs → Apple Push Notification service
```

### Project Structure
```
MessageAI/
├── App/
│   ├── MessageAIApp.swift (entry point)
│   └── ContentView.swift
├── Models/
│   ├── User.swift
│   ├── Conversation.swift
│   ├── Message.swift
│   └── AIFeatures/
├── Views/
│   ├── Auth/
│   ├── Conversations/
│   ├── Chat/
│   └── AI/
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── ConversationListViewModel.swift
│   └── ChatViewModel.swift
├── Services/
│   ├── SupabaseClient.swift
│   ├── RealtimeService.swift
│   ├── LocalStorageService.swift
│   └── AIService.swift
└── Utilities/
    ├── NetworkMonitor.swift
    └── Extensions/
```

### AI Integration
```
AI Stack:
├── Anthropic Claude API → LLM
├── Swift for function calling → Native tool use
└── Vector embeddings in PostgreSQL (pgvector) → RAG
4. Core Features - MVP (24 Hours)
4.1 Authentication
Teaching moment: We'll use Supabase Auth but handle it all in native Swift. Users sign in once and stay logged in.

Files to Create:

Models/User.swift
ViewModels/AuthViewModel.swift
Views/Auth/LoginView.swift
Views/Auth/SignUpView.swift
Implementation:

swift
// Models/User.swift
import Foundation

struct User: Identifiable, Codable {
    let id: UUID
    let email: String
    let username: String
    var displayName: String?
    var avatarUrl: String?
    let createdAt: Date
    var lastSeen: Date?
    var status: UserStatus
    
    enum UserStatus: String, Codable {
        case online, offline, away
    }
}

// Services/SupabaseClient.swift
import Foundation
import Supabase

class SupabaseClient {
    static let shared = SupabaseClient()
    
    let client: SupabaseClient
    
    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: "YOUR_SUPABASE_URL")!,
            supabaseKey: "YOUR_SUPABASE_ANON_KEY"
        )
    }
}

// ViewModels/AuthViewModel.swift
import Foundation
import Supabase

@MainActor
class AuthViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    
    private let supabase = SupabaseClient.shared.client
    
    func signUp(email: String, password: String, username: String) async {
        do {
            // Sign up with Supabase Auth
            let response = try await supabase.auth.signUp(
                email: email,
                password: password
            )
            
            // Create user profile in database
            let user = User(
                id: response.user.id,
                email: email,
                username: username,
                displayName: nil,
                avatarUrl: nil,
                createdAt: Date(),
                lastSeen: Date(),
                status: .online
            )
            
            try await supabase
                .from("users")
                .insert(user)
                .execute()
            
            self.currentUser = user
            self.isAuthenticated = true
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func signIn(email: String, password: String) async {
        do {
            let response = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            
            // Fetch user profile
            let user: User = try await supabase
                .from("users")
                .select()
                .eq("id", value: response.user.id)
                .single()
                .execute()
                .value
            
            self.currentUser = user
            self.isAuthenticated = true
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
Supabase Database Schema:

sql
-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id),
  email TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP,
  status TEXT DEFAULT 'offline'
);

-- Row Level Security (RLS)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view all profiles" ON users
  FOR SELECT USING (true);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);
UI Implementation:

swift
// Views/Auth/LoginView.swift
import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel = AuthViewModel()
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("MessageAI")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                
                Button("Sign In") {
                    Task {
                        await viewModel.signIn(email: email, password: password)
                    }
                }
                .buttonStyle(.borderedProminent)
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                NavigationLink("Don't have an account? Sign Up") {
                    SignUpView()
                }
            }
            .padding()
        }
    }
}
4.2 One-on-One Chat
Database Schema:

sql
-- Conversations table
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT,
  avatar_url TEXT,
  is_group BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Conversation participants
CREATE TABLE conversation_participants (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMP DEFAULT NOW(),
  last_read_at TIMESTAMP,
  PRIMARY KEY (conversation_id, user_id)
);

-- Messages table
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  message_type TEXT DEFAULT 'text',
  media_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  status TEXT DEFAULT 'sent',
  local_id TEXT,
  edited_at TIMESTAMP,
  deleted_at TIMESTAMP
);

-- RLS Policies
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Users can only see conversations they're part of
CREATE POLICY "Users can view own conversations" ON conversations
  FOR SELECT USING (
    id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can view messages in their conversations" ON messages
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert messages in their conversations" ON messages
  FOR INSERT WITH CHECK (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

-- Indexes for performance
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_participants_user ON conversation_participants(user_id);
Swift Models:

swift
// Models/Conversation.swift
import Foundation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var name: String?
    var avatarUrl: String?
    let isGroup: Bool
    let createdAt: Date
    var participants: [User]?
    var lastMessage: Message?
    var unreadCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case avatarUrl = "avatar_url"
        case isGroup = "is_group"
        case createdAt = "created_at"
        case participants
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
    }
}

// Models/Message.swift
import Foundation

struct Message: Identifiable, Codable, Hashable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let content: String
    let messageType: MessageType
    var mediaUrl: String?
    let createdAt: Date
    var status: MessageStatus
    var localId: String?
    var editedAt: Date?
    var deletedAt: Date?
    
    // For display purposes
    var sender: User?
    
    enum MessageType: String, Codable {
        case text, image, system
    }
    
    enum MessageStatus: String, Codable {
        case sending, sent, delivered, read, failed
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case content
        case messageType = "message_type"
        case mediaUrl = "media_url"
        case createdAt = "created_at"
        case status
        case localId = "local_id"
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
        case sender
    }
}
Chat ViewModel:

swift
// ViewModels/ChatViewModel.swift
import Foundation
import Supabase
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var isSending = false
    
    let conversation: Conversation
    private let supabase = SupabaseClient.shared.client
    private var realtimeChannel: RealtimeChannel?
    private var cancellables = Set<AnyCancellable>()
    
    init(conversation: Conversation) {
        self.conversation = conversation
    }
    
    func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response: [Message] = try await supabase
                .from("messages")
                .select("""
                    *,
                    sender:users!sender_id(*)
                """)
                .eq("conversation_id", value: conversation.id)
                .order("created_at", ascending: true)
                .execute()
                .value
            
            self.messages = response
            
        } catch {
            print("Error loading messages: \(error)")
        }
    }
    
    func sendMessage(content: String) async {
        guard !content.isEmpty else { return }
        
        isSending = true
        defer { isSending = false }
        
        let localId = UUID().uuidString
        
        // Optimistic UI update
        let optimisticMessage = Message(
            id: UUID(),
            conversationId: conversation.id,
            senderId: currentUserId, // Get from AuthViewModel
            content: content,
            messageType: .text,
            createdAt: Date(),
            status: .sending,
            localId: localId
        )
        
        messages.append(optimisticMessage)
        
        do {
            let insertedMessage: Message = try await supabase
                .from("messages")
                .insert([
                    "conversation_id": conversation.id,
                    "sender_id": currentUserId,
                    "content": content,
                    "local_id": localId
                ])
                .select()
                .single()
                .execute()
                .value
            
            // Replace optimistic message with real one
            if let index = messages.firstIndex(where: { $0.localId == localId }) {
                messages[index] = insertedMessage
            }
            
        } catch {
            // Mark message as failed
            if let index = messages.firstIndex(where: { $0.localId == localId }) {
                messages[index].status = .failed
            }
            print("Error sending message: \(error)")
        }
    }
    
    func subscribeToMessages() {
        realtimeChannel = supabase
            .channel("messages:\(conversation.id)")
            .on(
                .postgresChanges(
                    event: .insert,
                    schema: "public",
                    table: "messages",
                    filter: "conversation_id=eq.\(conversation.id)"
                )
            ) { [weak self] payload in
                guard let self = self,
                      let message = try? payload.decodeRecord() as Message else {
                    return
                }
                
                Task { @MainActor in
                    // Only add if not already present (avoid duplicates from optimistic UI)
                    if !self.messages.contains(where: { $0.id == message.id }) {
                        self.messages.append(message)
                    }
                }
            }
        
        Task {
            try? await realtimeChannel?.subscribe()
        }
    }
    
    func unsubscribe() {
        Task {
            try? await realtimeChannel?.unsubscribe()
        }
    }
}
Chat View:

swift
// Views/Chat/ChatView.swift
import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var scrollProxy: ScrollViewProxy?
    
    init(conversation: Conversation) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversation: conversation))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    scrollProxy = proxy
                }
            }
            
            // Input bar
            HStack(spacing: 12) {
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                
                Button {
                    Task {
                        await viewModel.sendMessage(content: messageText)
                        messageText = ""
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(messageText.isEmpty || viewModel.isSending)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle(viewModel.conversation.name ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadMessages()
            viewModel.subscribeToMessages()
        }
        .onDisappear {
            viewModel.unsubscribe()
        }
    }
}

struct MessageRow: View {
    let message: Message
    @State private var currentUserId: UUID // Get from environment or AuthViewModel
    
    var isOwnMessage: Bool {
        message.senderId == currentUserId
    }
    
    var body: some View {
        HStack {
            if isOwnMessage { Spacer() }
            
            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(isOwnMessage ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isOwnMessage ? .white : .primary)
                    .cornerRadius(16)
                
                HStack(spacing: 4) {
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if isOwnMessage {
                        statusIcon
                    }
                }
            }
            
            if !isOwnMessage { Spacer() }
        }
    }
    
    @ViewBuilder
    var statusIcon: some View {
        switch message.status {
        case .sending:
            ProgressView()
                .scaleEffect(0.6)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .delivered:
            Image(systemName: "checkmark.checkmark")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .read:
            Image(systemName: "checkmark.checkmark")
                .font(.caption2)
                .foregroundColor(.blue)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }
}
4.3 Local Storage with SwiftData
Teaching moment: SwiftData is Apple's new persistence framework (iOS 17+). For iOS 16, use Core Data. SwiftData saves data locally so your app works offline.

swift
// Models/LocalMessage.swift (for offline storage)
import SwiftData
import Foundation

@Model
class LocalMessage {
    @Attribute(.unique) var id: UUID
    var conversationId: UUID
    var senderId: UUID
    var content: String
    var createdAt: Date
    var syncStatus: SyncStatus
    var localId: String?
    
    enum SyncStatus: String, Codable {
        case pending, synced, failed
    }
    
    init(id: UUID, conversationId: UUID, senderId: UUID, content: String, createdAt: Date, syncStatus: SyncStatus, localId: String? = nil) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.content = content
        self.createdAt = createdAt
        self.syncStatus = syncStatus
        self.localId = localId
    }
}

// Services/LocalStorageService.swift
import SwiftData
import Foundation

@MainActor
class LocalStorageService {
    static let shared = LocalStorageService()
    
    private var container: ModelContainer
    private var context: ModelContext
    
    init() {
        do {
            container = try ModelContainer(for: LocalMessage.self)
            context = ModelContext(container)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }
    
    func saveMessage(_ message: Message) throws {
        let localMessage = LocalMessage(
            id: message.id,
            conversationId: message.conversationId,
            senderId: message.senderId,
            content: message.content,
            createdAt: message.createdAt,
            syncStatus: .synced,
            localId: message.localId
        )
        
        context.insert(localMessage)
        try context.save()
    }
    
    func getPendingMessages() -> [LocalMessage] {
        let descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate { $0.syncStatus == .pending }
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
    
    func updateSyncStatus(localId: String, status: LocalMessage.SyncStatus) throws {
        let descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate { $0.localId == localId }
        )
        
        if let message = try context.fetch(descriptor).first {
            message.syncStatus = status
            try context.save()
        }
    }
}
4.4 Network Monitoring & Offline Queue
Teaching moment: Network connectivity changes. We need to detect this and sync pending messages when online again.

swift
// Utilities/NetworkMonitor.swift
import Network
import Combine

class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = true
    @Published var connectionType: NWInterface.InterfaceType?
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}

// Services/MessageSyncService.swift
import Foundation
import Combine

@MainActor
class MessageSyncService: ObservableObject {
    static let shared = MessageSyncService()
    
    private let networkMonitor = NetworkMonitor()
    private let localStorage = LocalStorageService.shared
    private let supabase = SupabaseClient.shared.client
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // When network comes back online, sync pending messages
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    Task {
                        await self?.syncPendingMessages()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func syncPendingMessages() async {
        let pendingMessages = localStorage.getPendingMessages()
        
        for localMessage in pendingMessages {
            do {
                // Try to send to Supabase
                let _: Message = try await supabase
                    .from("messages")
                    .insert([
                        "conversation_id": localMessage.conversationId,
                        "sender_id": localMessage.senderId,
                        "content": localMessage.content,
                        "local_id": localMessage.localId ?? ""
                    ])
                    .select()
                    .single()
                    .execute()
                    .value
                
                // Mark as synced
                try localStorage.updateSyncStatus(
                    localId: localMessage.localId ?? "",
                    status: .synced
                )
                
            } catch {
                // Mark as failed
                try? localStorage.updateSyncStatus(
                    localId: localMessage.localId ?? "",
                    status: .failed
                )
                print("Failed to sync message: \(error)")
            }
        }
    }
}
4.5 Group Chat
Database Schema:

sql
-- Read receipts
CREATE TABLE read_receipts (
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  read_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);

-- RLS
ALTER TABLE read_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view read receipts in their conversations" ON read_receipts
  FOR SELECT USING (
    message_id IN (
      SELECT id FROM messages WHERE conversation_id IN (
        SELECT conversation_id FROM conversation_participants
        WHERE user_id = auth.uid()
      )
    )
  );
Swift Implementation:

swift
// Services/ConversationService.swift
@MainActor
class ConversationService {
    private let supabase = SupabaseClient.shared.client
    
    func createGroupConversation(name: String, participantIds: [UUID]) async throws -> Conversation {
        // Create conversation
        let conversation: Conversation = try await supabase
            .from("conversations")
            .insert([
                "name": name,
                "is_group": true
            ])
            .select()
            .single()
            .execute()
            .value
        
        // Add participants
        let participants = participantIds.map { userId in
            [
                "conversation_id": conversation.id,
                "user_id": userId
            ]
        }
        
        try await supabase
            .from("conversation_participants")
            .insert(participants)
            .execute()
        
        return conversation
    }
}
4.6 Push Notifications (APNs)
Teaching moment: Push notifications on iOS require Apple Push Notification service (APNs). You need certificates from Apple Developer account.

Setup Steps:

Enable Push Notifications capability in Xcode
Create APNs certificate in Apple Developer portal
Upload certificate to Supabase (or use a service like OneSignal)
swift
// App/MessageAIApp.swift
import SwiftUI
import UserNotifications

@main
struct MessageAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        
        return true
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Convert device token to string
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("Device token: \(token)")
        
        // Save to Supabase user profile
        Task {
            try? await SupabaseClient.shared.client
                .from("users")
                .update(["push_token": token])
                .eq("id", value: currentUserId)
                .execute()
        }
    }
}
Sending Notifications (from Edge Function):

typescript
// supabase/functions/send-notification/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  const { userId, title, body, conversationId } = await req.json()
  
  // Get user's push token from database
  const { data: user } = await supabase
    .from('users')
    .select('push_token')
    .eq('id', userId)
    .single()
  
  if (!user?.push_token) {
    return new Response('No push token', { status: 400 })
  }
  
  // Send to APNs
  await fetch('https://api.push.apple.com/3/device/' + user.push_token, {
    method: 'POST',
    headers: {
      'apns-topic': 'com.yourapp.messageai',
      'authorization': 'bearer ' + APNS_TOKEN
    },
    body: JSON.stringify({
      aps: {
        alert: { title, body },
        sound: 'default',
        badge: 1
      },
      conversationId
    })
  })
  
  return new Response('OK')
})
```

---

## 5. AI Features Implementation

**Teaching moment**: We'll call Claude API from Supabase Edge Functions to keep API keys secure. The iOS app makes requests to Edge Functions, not directly to Claude.

### Architecture:
```
iOS App → Supabase Edge Function → Claude API → Response
   ↓
Local RAG (fetch conversation history from DB)
5.1 Required AI Features (All 5 for Remote Team Professional)
Feature 1: Thread Summarization
Edge Function:

typescript
// supabase/functions/summarize-conversation/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import Anthropic from "@anthropic-ai/sdk"

serve(async (req) => {
  const { conversationId, messageCount = 50 } = await req.json()
  
  // Fetch recent messages
  const { data: messages } = await supabase
    .from('messages')
    .select(`
      content,
      created_at,
      sender:users!sender_id(display_name)
    `)
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: false })
    .limit(messageCount)
  
  // Format for Claude
  const conversation = messages
    .reverse()
    .map(m => `${m.sender.display_name}: ${m.content}`)
    .join('\n')
  
  // Call Claude
  const anthropic = new Anthropic({
    apiKey: Deno.env.get('ANTHROPIC_API_KEY')
  })
  
  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 1024,
    messages: [{
      role: 'user',
      content: `Summarize this conversation in 3-4 bullet points, focusing on key decisions, action items, and important topics discussed:\n\n${conversation}`
    }]
  })
  
  return new Response(
    JSON.stringify({ summary: response.content[0].text }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
iOS Service:

swift
// Services/AIService.swift
import Foundation

@MainActor
class AIService {
    private let supabase = SupabaseClient.shared.client
    
    struct SummaryResponse: Codable {
        let summary: String
    }
    
    func summarizeConversation(conversationId: UUID) async throws -> String {
        let response = try await supabase.functions
            .invoke(
                "summarize-conversation",
                options: FunctionInvokeOptions(
                    body: [
                        "conversationId": conversationId.uuidString
                    ]
                )
            )
        
        let decoder = JSONDecoder()
        let summaryResponse = try decoder.decode(SummaryResponse.self, from: response.data)
        return summaryResponse.summary
    }
}
UI Implementation:

swift
// Views/AI/ConversationSummaryView.swift
struct ConversationSummaryView: View {
    let conversationId: UUID
    @State private var summary: String?
    @State private var isLoading = false
    @State private var error: String?
    
    private let aiService = AIService()
    
    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView("Generating summary...")
            } else if let summary {
                ScrollView {
                    Text(summary)
                        .padding()
                }
            } else if let error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }
        }
        .navigationTitle("Conversation Summary")
        .toolbar {
            Button("Regenerate") {
                Task {
                    await loadSummary()
                }
            }
        }
        .task {
            await loadSummary()
        }
    }
    
    func loadSummary() async {
        isLoading = true
        error = nil
        
        do {
            summary = try await aiService.summarizeConversation(conversationId: conversationId)
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
}
Feature 2: Action Item Extraction
Edge Function:

typescript
// supabase/functions/extract-actions/index.ts
serve(async (req) => {
  const { conversationId } = await req.json()
  
  // Fetch messages
  const { data: messages } = await supabase
    .from('messages')
    .select('*, sender:users!sender_id(display_name, username)')
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: false })
    .limit(100)
  
  const conversation = messages
    .reverse()
    .map(m => `${m.sender.display_name}: ${m.content}`)
    .join('\n')
  
  const anthropic = new Anthropic({ apiKey: Deno.env.get('ANTHROPIC_API_KEY') })
  
  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 2048,
    messages: [{
      role: 'user',
      content: `Extract all action items from this conversation. For each action item, identify:
1. The task description
2. Who it's assigned to (if mentioned)
3. Any deadline or due date (if mentioned)

Return ONLY a valid JSON array in this exact format:
[
  {
    "task": "task description",
    "assignee": "username or null",
    "deadline": "ISO date string or null"
  }
]

Conversation:
${conversation}`
    }]
  })
  
  const jsonText = response.content[0].text
    .replace(/```json\n?/g, '')
    .replace(/```\n?/g, '')
    .trim()
  
  const actions = JSON.parse(jsonText)
  
  // Store in database
  for (const action of actions) {
    await supabase.from('action_items').insert({
      conversation_id: conversationId,
      task: action.task,
      assignee_username: action.assignee,
      deadline: action.deadline,
      status: 'pending'
    })
  }
  
  return new Response(JSON.stringify({ actions }), {
    headers: { 'Content-Type': 'application/json' }
  })
})
Database Schema:

sql
CREATE TABLE action_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id),
  message_id UUID REFERENCES messages(id),
  task TEXT NOT NULL,
  assignee_id UUID REFERENCES users(id),
  assignee_username TEXT,
  deadline TIMESTAMP,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP
);
Swift Model & Service:

swift
// Models/ActionItem.swift
struct ActionItem: Identifiable, Codable {
    let id: UUID
    let conversationId: UUID
    var messageId: UUID?
    let task: String
    var assigneeId: UUID?
    var assigneeUsername: String?
    var deadline: Date?
    var status: Status
    let createdAt: Date
    var completedAt: Date?
    
    enum Status: String, Codable {
        case pending, completed, cancelled
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case task
        case assigneeId = "assignee_id"
        case assigneeUsername = "assignee_username"
        case deadline
        case status
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

// Add to AIService.swift
struct ActionItemsResponse: Codable {
    let actions: [ActionItem]
}

func extractActionItems(conversationId: UUID) async throws -> [ActionItem] {
    let response = try await supabase.functions
        .invoke(
            "extract-actions",
            options: FunctionInvokeOptions(
                body: ["conversationId": conversationId.uuidString]
            )
        )
    
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let result = try decoder.decode(ActionItemsResponse.self, from: response.data)
    return result.actions
}
UI:

swift
// Views/AI/ActionItemsView.swift
struct ActionItemsView: View {
    let conversationId: UUID
    @State private var actionItems: [ActionItem] = []
    @State private var isLoading = false
    
    private let aiService = AIService()
    
    var body: some View {
        List {
            ForEach(actionItems) { item in
                ActionItemRow(item: item)
            }
        }
        .navigationTitle("Action Items")
        .toolbar {
            Button {
                Task { await extractActions() }
            } label: {
                Label("Extract", systemImage: "sparkles")
            }
        }
        .task {
            await loadActionItems()
        }
        .overlay {
            if isLoading {
                ProgressView("Extracting action items...")
            }
        }
    }
    
    func extractActions() async {
        isLoading = true
        do {
            let items = try await aiService.extractActionItems(conversationId: conversationId)
            actionItems = items
        } catch {
            print("Error extracting actions: \(error)")
        }
        isLoading = false
    }
    
    func loadActionItems() async {
        // Load from database
    }
}

struct ActionItemRow: View {
    let item: ActionItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.task)
                .font(.body)
            
            HStack {
                if let assignee = item.assigneeUsername {
                    Label(assignee, systemImage: "person")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let deadline = item.deadline {
                    Label(deadline, style: .date)
                        .font(.caption)
                        .foregroundColor(deadline < Date() ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
Feature 3: Smart Search (Semantic Search)
Teaching moment: Semantic search finds messages by meaning, not just keywords. We'll use embeddings - numerical representations of text meaning.

Database Setup:

sql
-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Add embedding column to messages
ALTER TABLE messages ADD COLUMN embedding vector(1536);

-- Create index for fast similarity search
CREATE INDEX ON messages USING ivfflat (embedding vector_cosine_ops);
Edge Function for Embeddings:

typescript
// supabase/functions/generate-embedding/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  const { text } = await req.json()
  
  // Call OpenAI Embeddings API
  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model: 'text-embedding-3-small',
      input: text
    })
  })
  
  const data = await response.json()
  return new Response(
    JSON.stringify({ embedding: data.data[0].embedding }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
Search Function:

typescript
// supabase/functions/semantic-search/index.ts
serve(async (req) => {
  const { query, conversationId } = await req.json()
  
  // Generate embedding for search query
  const embeddingResponse = await fetch(
    `${Deno.env.get('SUPABASE_URL')}/functions/v1/generate-embedding`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: query })
    }
  )
  
  const { embedding } = await embeddingResponse.json()
  
  // Search for similar messages
  const { data: results } = await supabase.rpc('search_messages', {
    query_embedding: embedding,
    match_threshold: 0.7,
    match_count: 10,
    conversation_filter: conversationId
  })
  
  return new Response(JSON.stringify({ results }), {
    headers: { 'Content-Type': 'application/json' }
  })
})
Database Function:

sql
-- Create similarity search function
CREATE OR REPLACE FUNCTION search_messages(
  query_embedding vector(1536),
  match_threshold float,
  match_count int,
  conversation_filter uuid
)
RETURNS TABLE (
  id uuid,
  content text,
  sender_id uuid,
  created_at timestamp,
  similarity float
)
LANGUAGE sql STABLE
AS $$
  SELECT
    id,
    content,
    sender_id,
    created_at,
    1 - (embedding <=> query_embedding) as similarity
  FROM messages
  WHERE conversation_id = conversation_filter
    AND 1 - (embedding <=> query_embedding) > match_threshold
  ORDER BY embedding <=> query_embedding
  LIMIT match_count;
$$;
Swift Implementation:

swift
// Add to AIService.swift
struct SearchResult: Codable {
    let id: UUID
    let content: String
    let senderId: UUID
    let createdAt: Date
    let similarity: Float
    
    enum CodingKeys: String, CodingKey {
        case id, content
        case senderId = "sender_id"
        case createdAt = "created_at"
        case similarity
    }
}

func semanticSearch(query: String, conversationId: UUID) async throws -> [SearchResult] {
    let response = try await supabase.functions
        .invoke(
            "semantic-search",
            options: FunctionInvokeOptions(
                body: [
                    "query": query,
                    "conversationId": conversationId.uuidString
                ]
            )
        )
    
    struct Response: Codable {
        let results: [SearchResult]
    }
    
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let result = try decoder.decode(Response.self, from: response.data)
    return result.results
}
Feature 4: Priority Message Detection
Edge Function:

typescript
// supabase/functions/detect-priority/index.ts
serve(async (req) => {
  const { conversationId } = await req.json()
  
  // Fetch recent unread messages
  const { data: messages } = await supabase
    .from('messages')
    .select('*, sender:users!sender_id(display_name)')
    .eq('conversation_id', conversationId)
    .gte('created_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
    .order('created_at', { ascending: false })
  
  const anthropic = new Anthropic({ apiKey: Deno.env.get('ANTHROPIC_API_KEY') })
  
  const messageList = messages.map(m => 
    `[ID: ${m.id}] ${m.sender.display_name}: ${m.content}`
  ).join('\n')
  
  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 2048,
    messages: [{
      role: 'user',
      content: `Analyze these messages and identify which are high priority. A message is high priority if it:
- Contains urgent requests or questions
- Mentions deadlines or time-sensitive information
- Has direct @mentions or assignments
- Indicates blockers or critical issues
- Requests important decisions

Return ONLY a JSON array of message IDs that are high priority:
["id1", "id2", ...]

Messages:
${messageList}`
    }]
  })
  
  const jsonText = response.content[0].text
    .replace(/```json\n?/g, '')
    .replace(/```\n?/g, '')
    .trim()
  
  const priorityIds = JSON.parse(jsonText)
  
  return new Response(JSON.stringify({ priorityIds }), {
    headers: { 'Content-Type': 'application/json' }
  })
})
Feature 5: Decision Tracking
Database Schema (already created above):

sql
CREATE TABLE decisions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id),
  message_id UUID REFERENCES messages(id),
  decision_text TEXT NOT NULL,
  decided_by UUID REFERENCES users(id),
  created_at TIMESTAMP DEFAULT NOW()
);
Edge Function:

typescript
// supabase/functions/track-decisions/index.ts
serve(async (req) => {
  const { conversationId } = await req.json()
  
  const { data: messages } = await supabase
    .from('messages')
    .select('*, sender:users!sender_id(id, display_name)')
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: false })
    .limit(100)
  
  const conversation = messages
    .reverse()
    .map(m => `[ID: ${m.id}] ${m.sender.display_name}: ${m.content}`)
    .join('\n')
  
  const anthropic = new Anthropic({ apiKey: Deno.env.get('ANTHROPIC_API_KEY') })
  
  const response = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 2048,
    messages: [{
      role: 'user',
      content: `Extract all decisions made in this conversation. Look for:
- Explicit decisions ("We decided to...", "Let's go with...")
- Consensus reached ("Sounds good", "Agreed")
- Final choices made

Return ONLY valid JSON:
[
  {
    "messageId": "uuid",
    "decision": "clear decision statement",
    "decidedBy": "username"
  }
]

Conversation:
${conversation}`
    }]
  })
  
  const jsonText = response.content[0].text
    .replace(/```json\n?/g, '')
    .replace(/```\n?/g, '')
    .trim()
  
  const decisions = JSON.parse(jsonText)
  
  // Store decisions
  for (const decision of decisions) {
    const message = messages.find(m => m.id === decision.messageId)
    if (message) {
      await supabase.from('decisions').insert({
        conversation_id: conversationId,
        message_id: decision.messageId,
        decision_text: decision.decision,
        decided_by: message.sender.id
      })
    }
  }
  
  return new Response(JSON.stringify({ decisions }), {
    headers: { 'Content-Type': 'application/json' }
  })
})
5.2 Advanced AI Feature: Proactive Assistant
Teaching moment: This is a more complex AI agent that proactively detects when scheduling is needed and suggests meeting times.

Edge Function:

typescript
// supabase/functions/proactive-assistant/index.ts
serve(async (req) => {
  const { conversationId, lastMessageId } = await req.json()
  
  // Get recent context (last 20 messages)
  const { data: messages } = await supabase
    .from('messages')
    .select('*, sender:users!sender_id(display_name)')
    .eq('conversation_id', conversationId)
    .lte('id', lastMessageId)
    .order('created_at', { ascending: false })
    .limit(20)
  
  const conversation = messages
    .reverse()
    .map(m => `${m.sender.display_name}: ${m.content}`)
    .join('\n')
  
  const anthropic = new Anthropic({ apiKey: Deno.env.get('ANTHROPIC_API_KEY') })
  
  // Detect if scheduling assistance is needed
  const analysisResponse = await anthropic.messages.create({
    model: 'claude-sonnet-4-20250514',
    max_tokens: 1024,
    messages: [{
      role: 'user',
      content: `Analyze this conversation and determine if scheduling assistance would be helpful.

Return JSON:
{
  "needsScheduling": boolean,
  "reason": "brief explanation",
  "suggestedAction": "what to offer"
}

Conversation:
${conversation}`
    }]
  })
  
  const analysis = JSON.parse(
    analysisResponse.content[0].text
      .replace(/```json\n?/g, '')
      .replace(/```\n?/g, '')
      .trim()
  )
  
  if (analysis.needsScheduling) {
    // Generate meeting time suggestions
    // This would integrate with calendar APIs in production
    const suggestions = {
      message: "I noticed you're trying to schedule a meeting. Here are some available times:",
      times: [
        "Tomorrow at 2pm EST",
        "Wednesday at 10am EST",
        "Friday at 3pm EST"
      ]
    }
    
    return new Response(JSON.stringify({ 
      shouldAssist: true,
      suggestions 
    }), {
      headers: { 'Content-Type': 'application/json' }
    })
  }
  
  return new Response(JSON.stringify({ shouldAssist: false }), {
    headers: { 'Content-Type': 'application/json' }
  })
})
Swift Implementation:

swift
// Services/ProactiveAssistantService.swift
@MainActor
class ProactiveAssistantService: ObservableObject {
    @Published var suggestion: AssistantSuggestion?
    
    private let supabase = SupabaseClient.shared.client
    
    struct AssistantSuggestion: Codable {
        let message: String
        let times: [String]?
        let action: String?
    }
    
    func checkForSuggestions(conversationId: UUID, lastMessageId: UUID) async {
        do {
            let response = try await supabase.functions
                .invoke(
                    "proactive-assistant",
                    options: FunctionInvokeOptions(
                        body: [
                            "conversationId": conversationId.uuidString,
                            "lastMessageId": lastMessageId.uuidString
                        ]
                    )
                )
            
            struct Response: Codable {
                let shouldAssist: Bool
                let suggestions: AssistantSuggestion?
            }
            
            let result = try JSONDecoder().decode(Response.self, from: response.data)
            
            if result.shouldAssist, let suggestions = result.suggestions {
                self.suggestion = suggestions
            }
            
        } catch {
            print("Error checking for suggestions: \(error)")
        }
    }
}
UI Integration:

swift
// Add to ChatView.swift
@StateObject private var assistantService = ProactiveAssistantService()

// In the view body, add this overlay:
.overlay(alignment: .top) {
    if let suggestion = assistantService.suggestion {
        AssistantSuggestionBanner(suggestion: suggestion) {
            assistantService.suggestion = nil
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
// After sending a message, check for suggestions
.onChange(of: viewModel.messages.count) { _, _ in
    if let lastMessage = viewModel.messages.last {
        Task {
            await assistantService.checkForSuggestions(
                conversationId: conversation.id,
                lastMessageId: lastMessage.id
            )
        }
    }
}

struct AssistantSuggestionBanner: View {
    let suggestion: ProactiveAssistantService.AssistantSuggestion
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("AI Assistant")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
            }
            
            Text(suggestion.message)
                .font(.subheadline)
            
            if let times = suggestion.times {
                ForEach(times, id: \.self) { time in
                    Button(time) {
                        // Handle time selection
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
        .padding()
    }
}
6. Implementation Timeline
Day 1 (MVP - 24 hours)
Hour 0-2: Setup

 Create new Xcode project (iOS 17.0+)
 Set up Supabase project
 Install Swift Supabase SDK via SPM
 Create database schema
Hour 2-6: Authentication

 Build User model
 Create AuthViewModel
 Implement Login/SignUp views
 Test authentication flow
Hour 6-12: Basic Chat

 Create Message and Conversation models
 Build ChatViewModel with send/receive
 Create ChatView UI
 Implement message list
Hour 12-18: Real-time + Offline

 Set up Realtime subscriptions
 Implement SwiftData for local storage
 Build message sync service
 Test offline scenarios
Hour 18-22: Group Chat & Polish

 Add group chat functionality
 Implement read receipts
 Add presence indicators
 Test with multiple devices
Hour 22-24: Push Notifications

 Set up APNs
 Implement notification handling
 Test foreground/background notifications
Days 2-3 (Core Feature Polish)
 Optimistic UI refinements
 Error handling and retry logic
 Message editing/deletion
 Image/media support
 Profile pictures
 UI/UX polish
 Network status indicators
 Typing indicators
Days 4-5 (AI Features)
 Set up Claude API access
 Create Supabase Edge Functions for each AI feature
 Implement thread summarization
 Build action item extraction
 Add semantic search with embeddings
 Implement priority detection
 Add decision tracking
 Create AI feature UIs
Days 6-7 (Advanced AI & Final Polish)
 Implement proactive assistant
 End-to-end testing
 Performance optimization
 Deploy to TestFlight
 Record demo video
 Write persona brainlift document
7. Key Technical Decisions
Why SwiftUI?
Native performance: Direct access to iOS frameworks
Modern Swift: async/await, Combine, SwiftData
Best iOS experience: Native animations, gestures, accessibility
Easier deployment: Single platform to focus on
Supabase Integration Pattern
Teaching moment: We'll create a singleton client that manages all Supabase interactions.

swift
// Services/SupabaseClient.swift - Full implementation
import Foundation
import Supabase
import Combine

class SupabaseClient: ObservableObject {
    static let shared = SupabaseClient()
    
    let client: SupabaseClient
    
    private init() {
        guard let url = URL(string: ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? "") else {
            fatalError("Missing SUPABASE_URL")
        }
        
        guard let anonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] else {
            fatalError("Missing SUPABASE_ANON_KEY")
        }
        
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey
        )
    }
}
```

### Message Sync Strategy
```
Optimistic UI Flow:
1. User taps send → Message appears immediately with status: .sending
2. Save to local SwiftData with syncStatus: .pending
3. POST to Supabase in background
4. On success: Update status to .sent, mark syncStatus: .synced
5. On failure: Update status to .failed, keep syncStatus: .pending
6. Background sync retries pending messages when online

Realtime Sync:
- Subscribe to Supabase Realtime for new messages
- Update UI immediately when messages arrive
- Deduplicate (don't show same message twice from optimistic + realtime)
Local Storage Strategy
swift
// Use SwiftData for iOS 17+
@Model
class LocalMessage {
    var id: UUID
    var conversationId: UUID
    var content: String
    var syncStatus: SyncStatus
    // ...
}

// For iOS 16, use Core Data with similar structure
```

---

## 8. Testing Strategy

### MVP Testing Checklist
- [ ] Two physical devices can chat in real-time
- [ ] Messages persist after force quit
- [ ] Offline messages sync when reconnected
- [ ] Group chat works with 3+ people
- [ ] Read receipts show correctly
- [ ] Push notifications deliver (foreground & background)
- [ ] App handles poor network gracefully

### AI Feature Testing
- [ ] Summarization is accurate and concise
- [ ] Action items are correctly extracted
- [ ] Semantic search returns relevant results
- [ ] Priority detection identifies urgent messages
- [ ] Decision tracking captures key decisions
- [ ] Proactive assistant suggests at right times

### Edge Cases
- [ ] Empty conversations
- [ ] Very long messages (1000+ characters)
- [ ] Rapid-fire messages (20+ in 10 seconds)
- [ ] Special characters and emojis
- [ ] Mixed languages (if relevant to persona)
- [ ] Network transitions (WiFi → Cellular)
- [ ] Low battery mode
- [ ] Background app refresh disabled

---

## 9. Deployment

### TestFlight Deployment

**Teaching moment**: TestFlight lets you distribute your app to testers before App Store release.

**Steps**:
1. **Archive the app** in Xcode
2. **Upload to App Store Connect**
3. **Add testers** via email
4. **Testers install TestFlight app** and accept invitation
5. **Update regularly** as you improve the app

**Xcode Archive Process**:
```
1. Product → Archive
2. Wait for archive to complete
3. Distribute App → App Store Connect
4. Upload
5. Wait for processing
6. Add to TestFlight
```

### Required Assets
- [ ] App icon (1024x1024)
- [ ] Launch screen
- [ ] Privacy policy URL (for App Store)
- [ ] Screenshots for demo

---

## 10. Success Criteria

### MVP Success (Must Have)
✅ Two users can exchange messages in real-time  
✅ Messages persist after app restart  
✅ Offline messages queue and sync  
✅ Group chat works with 3+ participants  
✅ Read receipts function correctly  
✅ Push notifications deliver  
✅ App handles lifecycle events properly  

### Final Success
✅ All 5 required AI features work reliably  
✅ Advanced AI feature (proactive assistant) demonstrates value  
✅ App feels polished and responsive  
✅ No message loss under any conditions  
✅ Deployed on TestFlight with demo video  

---

## 11. File Structure Overview
```
MessageAI/
├── MessageAI.xcodeproj
├── MessageAI/
│   ├── App/
│   │   ├── MessageAIApp.swift
│   │   ├── AppDelegate.swift
│   │   └── ContentView.swift
│   │
│   ├── Models/
│   │   ├── User.swift
│   │   ├── Conversation.swift
│   │   ├── Message.swift
│   │   ├── ActionItem.swift
│   │   ├── Decision.swift
│   │   └── LocalMessage.swift (SwiftData)
│   │
│   ├── Views/
│   │   ├── Auth/
│   │   │   ├── LoginView.swift
│   │   │   └── SignUpView.swift
│   │   ├── Conversations/
│   │   │   ├── ConversationListView.swift
│   │   │   └── ConversationRow.swift
│   │   ├── Chat/
│   │   │   ├── ChatView.swift
│   │   │   ├── MessageRow.swift
│   │   │   └── MessageInputView.swift
│   │   └── AI/
│   │       ├── ConversationSummaryView.swift
│   │       ├── ActionItemsView.swift
│   │       ├── SemanticSearchView.swift
│   │       ├── DecisionTimelineView.swift
│   │       └── AssistantSuggestionBanner.swift
│   │
│   ├── ViewModels/
│   │   ├── AuthViewModel.swift
│   │   ├── ConversationListViewModel.swift
│   │   ├── ChatViewModel.swift
│   │   └── AIFeaturesViewModel.swift
│   │
│   ├── Services/
│   │   ├── SupabaseClient.swift
│   │   ├── RealtimeService.swift
│   │   ├── LocalStorageService.swift
│   │   ├── MessageSyncService.swift
│   │   ├── AIService.swift
│   │   ├── ProactiveAssistantService.swift
│   │   └── ConversationService.swift
│   │
│   ├── Utilities/
│   │   ├── NetworkMonitor.swift
│   │   ├── Extensions/
│   │   │   ├── Date+Extensions.swift
│   │   │   └── View+Extensions.swift
│   │   └── Constants.swift
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
│
└── Supabase/
    └── functions/
        ├── summarize-conversation/
        ├── extract-actions/
        ├── generate-embedding/
        ├── semantic-search/
        ├── detect-priority/
        ├── track-decisions/
        └── proactive-assistant/
12. Next Steps
Now that we have the complete PRD, here's how to get started:

Option 1: Start with Setup
Create Supabase project
Set up database schema
Create Xcode project
Install dependencies
Option 2: Start with a Feature
Build authentication first (login/signup)
Then add basic messaging
Then real-time sync
Then AI features
Option 3: Get Help with Specific Section
Tell me which part you want to dive into:

Database schema setup?
Authentication implementation?
Real-time messaging?
AI feature integration?
Specific AI feature deep dive?
What would you like to tackle first?

any questions for me? i will eventually use vercel ai sdk


Identified architectural implications of Vercel AI SDK integration with iOS.



Great! I have several important questions that will help me tailor the implementation strategy for you:

Technical Background
Swift/SwiftUI Experience
Have you built iOS apps with SwiftUI before?
If not, what's your primary programming background? (This helps me adjust explanations)
Vercel AI SDK Integration ⭐ Important
Since Vercel AI SDK is JavaScript/TypeScript, how are you planning to integrate it?
Option A: Use Vercel Edge Functions for AI (separate from Supabase)?
Option B: Use Vercel AI SDK within Supabase Edge Functions (they run Deno)?
Option C: Something else?
This affects your architecture significantly:
   Option A:
   iOS App → Supabase (messages/auth) + Vercel (AI features)
   
   Option B:
   iOS App → Supabase (everything, including AI via Edge Functions using Vercel SDK)
AI Provider
Are you using Claude API, OpenAI, or something else?
Do you already have API keys?
Persona & Features
Which persona are you choosing?
Remote Team Professional (thread summaries, action items)
International Communicator (translation, language features)
Busy Parent/Caregiver (calendar, scheduling)
Content Creator/Influencer (DM categorization, auto-responses)
Which advanced AI feature?
Multi-Step Agent (autonomous planning)
Proactive Assistant (auto-suggestions)
Context-Aware Smart Replies (style learning)
Intelligent Processing (structured data extraction)
Development Setup
Apple Developer Account
Do you have one? ($99/year required for TestFlight)
Or are you okay testing with Simulator + local builds only?
Testing Devices
Do you have 2+ physical iPhones/iPads for testing?
Or will you use Simulator + asking friends to test?
Time Commitment
Are you doing this full-time for 7 days or part-time?
What's your actual availability? (Helps me set realistic milestones)
Project Scope
MVP Scope Flexibility
Are you okay shipping iOS-only for v1?
Or do you need it to work on Android too? (This would require React Native)
Budget Awareness
Are you aware of costs?
Claude API: ~$3 per million input tokens
OpenAI Embeddings: ~$0.13 per million tokens
Supabase: Free tier should work, but may need Pro ($25/mo) for production
Apple Developer: $99/year
What's your comfort level here?
Most Critical Questions
If you only answer 3, make it these:

How are you integrating Vercel AI SDK with SwiftUI? (Architecture decision)
Which persona are you building for? (Determines all AI features)
What's your Swift/SwiftUI experience level? (How much I should explain)
Let me know your answers and I'll update the PRD with the optimal architecture for your setup!


For Vercel AI SDK projects, Vercel Edge Functions offer seamless integration, a familiar JavaScript/Node.js environment, and optimal performance by running on the same infrastructure as your frontend. Supabase Edge Functions, while powerful, introduce a different runtime (Deno) and are better suited

pasted

yes, have built apps with swiftui,.. review this logic:


Validated architecture choice for Supabase Edge Functions hosting.
38s













Reviewing the logic - YES, it's absolutely sound. This is the optimal architecture for your use case. Let me break down why:

✅ The Logic is Correct
Your Architecture:

SwiftUI App (iOS)
    ↓ (URLSession API calls)
Supabase Edge Functions (Deno + Vercel AI SDK)
    ↓ (direct, co-located access)
Supabase Backend (PostgreSQL, Auth, Realtime, Storage)
Why This is Optimal:
1. Database Proximity = Performance

AI agents need conversation history for context (RAG)
Every AI request will query your Supabase DB for messages
Co-located Edge Function → DB = <10ms latency
External Vercel → Supabase = 50-200ms latency
For a messaging app with streaming AI, this matters enormously
2. Unified Backend Management

bash
# One CLI for everything
supabase functions deploy summarize-conversation
supabase db push
supabase gen types typescript

# vs split management:
vercel deploy        # for AI
supabase db push     # for data
3. Vercel AI SDK Works Perfectly in Deno

typescript
// supabase/functions/ai-chat/index.ts
import { streamText } from 'npm:ai'  // ← Deno supports npm packages
import { anthropic } from 'npm:@ai-sdk/anthropic'

Deno.serve(async (req) => {
  const { messages } = await req.json()
  
  const result = await streamText({
    model: anthropic('claude-sonnet-4-20250514'),
    messages,
  })
  
  return result.toDataStreamResponse()
})
```

**4. Your SwiftUI App Doesn't Care**
- Whether it's Supabase or Vercel Edge Functions, your Swift code makes the same `URLSession` requests
- The choice only affects backend performance, not client code

## ❌ Why Vercel Edge Functions Would Be Suboptimal

**The document correctly identifies this as an anti-pattern:**
```
[SwiftUI App] 
    → [Vercel Edge Function]  ← AI logic here
          → (network hop over internet)
              → [Supabase DB]  ← Data is here
```

- **Added latency**: Every AI request has an extra roundtrip
- **No benefit**: Vercel's advantage is co-location with Vercel-hosted frontends (Next.js apps)
- Your SwiftUI app is native iOS, not hosted on Vercel
- You'd be paying for two separate platforms

## Updated PRD Architecture Section

Let me update the technical stack in your PRD:

### Technical Architecture (Revised)
```
iOS App:
├── SwiftUI (UI framework)
├── Swift Concurrency (async/await)
├── SwiftData (local storage)
└── Supabase Swift SDK (backend client)

Backend (Supabase):
├── PostgreSQL (messages, users, conversations)
├── Realtime (WebSocket subscriptions)
├── Auth (user authentication)
├── Storage (images, media)
└── Edge Functions (Deno runtime)
    └── Vercel AI SDK (AI agent orchestration)

AI Stack:
├── Vercel AI SDK (tool use, streaming, agents)
├── Anthropic Claude API (LLM)
└── OpenAI Embeddings (semantic search)
Key Dependencies for Supabase Edge Functions
In your Supabase Edge Functions:

typescript
// supabase/functions/_shared/deps.ts
export { streamText, generateText, tool } from 'npm:ai@3.4.29'
export { anthropic } from 'npm:@ai-sdk/anthropic@1.0.1'
export { createClient } from 'jsr:@supabase/supabase-js@2'
Example Edge Function with Vercel AI SDK:

typescript
// supabase/functions/ai-chat/index.ts
import { streamText } from 'npm:ai'
import { anthropic } from 'npm:@ai-sdk/anthropic'
import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  // Get auth from request
  const authHeader = req.headers.get('Authorization')!
  
  // Create Supabase client (auto-configured in Edge Functions)
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } }
  )
  
  const { conversationId, message } = await req.json()
  
  // Fetch conversation history from DB (co-located = fast!)
  const { data: messages } = await supabase
    .from('messages')
    .select('content, sender_id')
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: true })
    .limit(20)
  
  // Build context for AI
  const chatHistory = messages.map(m => ({
    role: m.sender_id === userId ? 'user' : 'assistant',
    content: m.content
  }))
  
  // Stream response using Vercel AI SDK
  const result = await streamText({
    model: anthropic('claude-sonnet-4-20250514'),
    messages: [...chatHistory, { role: 'user', content: message }],
    temperature: 0.7,
  })
  
  return result.toDataStreamResponse()
})
From SwiftUI:

swift
// Swift code to call this function
func sendMessageToAI(message: String, conversationId: UUID) async throws {
    let response = try await supabase.functions
        .invoke(
            "ai-chat",
            options: FunctionInvokeOptions(
                body: [
                    "conversationId": conversationId.uuidString,
                    "message": message
                ]
            )
        )
    
    // Handle streaming response
    // ... (streaming parsing logic)
}
Should I Update Anything Else?
Based on this architecture decision, should I:

Update all Edge Function examples to explicitly show Vercel AI SDK imports with npm: prefix?
Add a section on Vercel AI SDK tools/agents in Supabase Edge Functions?
Show streaming response handling in SwiftUI (this is complex)?
Add cost comparison between this setup vs alternatives?
Your logic is rock solid. This is the right architecture. Want me to dive deeper into any specific part?

would bun be bettern than npm?
add a seciton on Vercel AI SDK tools/agents in Supabase Edge Functions
don't show streaming yet, will have task list and architecture deeper later
aware of costs
can ship ios only, no android or web
fulltime with ai agents helping
can use physical testing devices, multiple
do have apple acct
i have api keys, openai specifically
busy parent/caregiver with proactive assistant

Clarified technical constraints and refined proactive assistant persona requirements.
5m, 33s



Updated PRD Sections
1. Bun vs npm in Supabase Edge Functions
Short answer: Use npm: prefix - Bun isn't applicable here.

Teaching moment: Supabase Edge Functions run on Deno, not Node.js or Bun. Deno has its own module system:

typescript
// Deno's import prefixes in Supabase Edge Functions:

// ✅ npm packages (most common)
import { streamText } from 'npm:ai@3.4.29'
import { anthropic } from 'npm:@ai-sdk/anthropic@1.0.1'

// ✅ JSR (JavaScript Registry) - Deno's native registry
import { createClient } from 'jsr:@supabase/supabase-js@2'

// ✅ Direct URLs
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
```

**Why not Bun?**
- Bun is a separate JavaScript runtime (like Node.js)
- Supabase chose Deno for Edge Functions because it's built for edge computing
- You can't run Bun inside Deno - they're alternative runtimes

**Performance note**: Deno's `npm:` imports are actually quite fast. The first import caches the package, subsequent cold starts are quick.

---

## 2. Your Chosen Persona & Features

### Persona: Busy Parent/Caregiver

**Pain Points:**
- Juggling multiple schedules (kids, appointments, activities)
- Missing important dates and deadlines
- Decision fatigue from constant coordination
- Information overload from multiple group chats

### Required AI Features (All 5):

1. **Smart Calendar Extraction**
   - Automatically detect dates, times, appointments in messages
   - "Soccer practice Tuesday at 4pm" → Calendar event suggestion
   - Extract school events, doctor appointments, playdates

2. **Decision Summarization**
   - Track decisions made in group chats ("We're doing pizza Friday")
   - Parent group decisions about events, carpools, activities
   - Show timeline of what was decided and by whom

3. **Priority Message Highlighting**
   - Flag urgent messages (school closures, last-minute changes)
   - Highlight messages needing responses (RSVP requests)
   - Surface important info from long threads

4. **RSVP Tracking**
   - Detect RSVP requests ("Can your kid come to the birthday party?")
   - Track who responded, who hasn't
   - Remind about unanswered RSVPs

5. **Deadline/Reminder Extraction**
   - Pull out deadlines ("Permission slip due Friday")
   - School forms, payment deadlines, signup cutoffs
   - Create actionable reminders

### Advanced Feature: Proactive Assistant

**Capabilities:**
- Detects scheduling conflicts automatically
- Suggests solutions when conflicts arise
- Offers to create calendar events from messages
- Proactively reminds about upcoming deadlines
- Suggests carpools/coordination opportunities

**Example Scenarios:**
```
Scenario 1: Conflict Detection
Messages: "Dance recital is Saturday at 2pm" + "Tommy's birthday party Saturday at 2pm"
Assistant: "⚠️ Schedule conflict detected. Both events are Saturday at 2pm. 
Options:
- Attend dance recital (2-4pm), join birthday party late
- Skip dance recital warmup, arrive by performance time
- Decline birthday party"

Scenario 2: Smart Scheduling
Message: "Anyone want to carpool to soccer practice Tuesday?"
Assistant: "🚗 I noticed you both go to soccer practice Tuesdays at 4pm. 
Sarah lives 0.3 miles from you. Would you like me to suggest a carpool arrangement?"

Scenario 3: Deadline Reminder
3 days before: "📋 Reminder: Field trip permission slip due Friday. 
I noticed you haven't responded to Mrs. Johnson's message yet."
3. Vercel AI SDK Tools/Agents in Supabase Edge Functions
Teaching moment: The Vercel AI SDK has a powerful "tools" system (also called "function calling"). This lets your AI agent take actions, not just generate text.

What are AI Tools?
Tools give your AI agent superpowers - the ability to:

Query databases
Call APIs
Perform calculations
Execute custom logic
Example: Instead of just saying "I found 3 conflicts," the agent can actually query your calendar, compare events, and return structured data.

Basic Tool Structure
typescript
// supabase/functions/proactive-assistant/index.ts
import { generateText, tool } from 'npm:ai'
import { anthropic } from 'npm:@ai-sdk/anthropic'
import { z } from 'npm:zod'  // For schema validation
import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!
  )
  
  const { conversationId, userId } = await req.json()
  
  // Define tools the AI can use
  const result = await generateText({
    model: anthropic('claude-sonnet-4-20250514'),
    maxTokens: 2000,
    
    system: `You are a proactive assistant for busy parents. 
    Analyze messages and proactively detect:
    - Schedule conflicts
    - Missed RSVPs
    - Upcoming deadlines
    - Coordination opportunities`,
    
    messages: [
      { role: 'user', content: 'Check for any issues I should know about' }
    ],
    
    tools: {
      // Tool 1: Get recent messages
      getRecentMessages: tool({
        description: 'Get recent messages from a conversation to analyze',
        parameters: z.object({
          limit: z.number().describe('Number of messages to retrieve')
        }),
        execute: async ({ limit }) => {
          const { data } = await supabase
            .from('messages')
            .select('*, sender:users(display_name)')
            .eq('conversation_id', conversationId)
            .order('created_at', { ascending: false })
            .limit(limit)
          
          return data
        }
      }),
      
      // Tool 2: Extract calendar events from messages
      extractCalendarEvents: tool({
        description: 'Extract date/time/event information from message text',
        parameters: z.object({
          messageText: z.string().describe('The message to extract events from')
        }),
        execute: async ({ messageText }) => {
          // Use another AI call or regex to extract structured data
          const extraction = await generateText({
            model: anthropic('claude-sonnet-4-20250514'),
            messages: [{
              role: 'user',
              content: `Extract calendar events from this message. Return JSON:
              { "events": [{ "title": string, "date": ISO date, "time": string, "location": string }] }
              
              Message: ${messageText}`
            }]
          })
          
          return JSON.parse(extraction.text)
        }
      }),
      
      // Tool 3: Check for schedule conflicts
      checkScheduleConflicts: tool({
        description: 'Check if events conflict with existing calendar',
        parameters: z.object({
          events: z.array(z.object({
            title: z.string(),
            date: z.string(),
            time: z.string()
          }))
        }),
        execute: async ({ events }) => {
          // Query user's actual calendar (stored in DB or via API)
          const { data: existingEvents } = await supabase
            .from('calendar_events')
            .select('*')
            .eq('user_id', userId)
            .gte('date', new Date().toISOString())
          
          // Check for conflicts
          const conflicts = []
          for (const newEvent of events) {
            for (const existing of existingEvents || []) {
              if (newEvent.date === existing.date && 
                  timesOverlap(newEvent.time, existing.time)) {
                conflicts.push({
                  event1: newEvent.title,
                  event2: existing.title,
                  date: newEvent.date,
                  time: newEvent.time
                })
              }
            }
          }
          
          return { conflicts, count: conflicts.length }
        }
      }),
      
      // Tool 4: Get pending RSVPs
      getPendingRSVPs: tool({
        description: 'Find RSVP requests that haven\'t been answered',
        parameters: z.object({}),
        execute: async () => {
          const { data: rsvps } = await supabase
            .from('rsvp_tracking')
            .select('*, message:messages(*)')
            .eq('user_id', userId)
            .eq('status', 'pending')
            .order('deadline', { ascending: true })
          
          return rsvps
        }
      })
    }
  })
  
  return new Response(
    JSON.stringify({ 
      analysis: result.text,
      toolCalls: result.toolCalls,
      warnings: result.warnings
    }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})

// Helper function
function timesOverlap(time1: string, time2: string): boolean {
  // Parse times and check overlap
  // Simplified - would need proper time parsing
  return time1 === time2
}
```

### How Tool Execution Works

**Teaching moment**: Here's the flow when you use tools:
```
1. You send prompt to AI with available tools
   ↓
2. AI decides which tools to call (if any)
   ↓
3. Vercel AI SDK executes those tools
   ↓
4. Results are sent back to AI
   ↓
5. AI uses results to generate final response
   ↓
6. You get the response + tool results
The AI SDK handles this loop automatically - you don't manually orchestrate it.

Multi-Step Agent Example
For your Proactive Assistant, you want multi-step reasoning:

typescript
// supabase/functions/multi-step-assistant/index.ts
import { generateText, tool } from 'npm:ai'
import { anthropic } from 'npm:@ai-sdk/anthropic'
import { z } from 'npm:zod'

Deno.serve(async (req) => {
  const { conversationId, userId } = await req.json()
  
  // Multi-step agent with maxSteps
  const result = await generateText({
    model: anthropic('claude-sonnet-4-20250514'),
    maxTokens: 4000,
    maxSteps: 5,  // ← Agent can use tools up to 5 times
    
    system: `You are a proactive scheduling assistant for busy parents.
    Your job:
    1. Analyze recent messages for scheduling info
    2. Check for conflicts with existing events
    3. Identify missed RSVPs or deadlines
    4. Provide actionable recommendations
    
    Be proactive but not overwhelming. Focus on the most important 1-2 issues.`,
    
    messages: [
      { 
        role: 'user', 
        content: 'Analyze my recent messages and let me know if there are any scheduling issues or things I need to handle.' 
      }
    ],
    
    tools: {
      getMessages: tool({
        description: 'Retrieve recent messages from conversation',
        parameters: z.object({
          days: z.number().describe('Number of days of history')
        }),
        execute: async ({ days }) => {
          const since = new Date()
          since.setDate(since.getDate() - days)
          
          const { data } = await supabase
            .from('messages')
            .select('content, created_at, sender:users(display_name)')
            .eq('conversation_id', conversationId)
            .gte('created_at', since.toISOString())
            .order('created_at', { ascending: true })
          
          return data?.map(m => 
            `[${m.created_at}] ${m.sender.display_name}: ${m.content}`
          ).join('\n')
        }
      }),
      
      extractEvents: tool({
        description: 'Extract structured event data from text',
        parameters: z.object({
          text: z.string()
        }),
        execute: async ({ text }) => {
          // This could be another AI call or pattern matching
          const events = []
          
          // Simple regex for demo (would be more sophisticated)
          const datePattern = /(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday).*?(\d{1,2}:\d{2}\s*(?:am|pm|AM|PM))/gi
          const matches = [...text.matchAll(datePattern)]
          
          for (const match of matches) {
            events.push({
              day: match[1],
              time: match[2],
              rawText: match[0]
            })
          }
          
          return events
        }
      }),
      
      checkCalendar: tool({
        description: 'Check user calendar for conflicts',
        parameters: z.object({
          date: z.string().describe('Date to check (YYYY-MM-DD)'),
          time: z.string().describe('Time to check')
        }),
        execute: async ({ date, time }) => {
          const { data: existingEvents } = await supabase
            .from('calendar_events')
            .select('*')
            .eq('user_id', userId)
            .eq('date', date)
          
          return {
            hasConflict: existingEvents && existingEvents.length > 0,
            events: existingEvents
          }
        }
      }),
      
      getRSVPStatus: tool({
        description: 'Get status of pending RSVPs',
        parameters: z.object({}),
        execute: async () => {
          const { data } = await supabase
            .from('rsvp_tracking')
            .select(`
              *,
              event_name,
              deadline,
              requested_by:users(display_name)
            `)
            .eq('user_id', userId)
            .eq('status', 'pending')
            .order('deadline', { ascending: true })
          
          return data
        }
      }),
      
      createReminder: tool({
        description: 'Create a reminder for the user',
        parameters: z.object({
          title: z.string(),
          reminderTime: z.string().describe('When to remind (ISO datetime)'),
          priority: z.enum(['low', 'medium', 'high'])
        }),
        execute: async ({ title, reminderTime, priority }) => {
          const { data } = await supabase
            .from('reminders')
            .insert({
              user_id: userId,
              title,
              reminder_time: reminderTime,
              priority,
              status: 'pending'
            })
            .select()
            .single()
          
          return { success: true, reminderId: data.id }
        }
      })
    }
  })
  
  // The result contains both the final text and all tool calls
  return new Response(
    JSON.stringify({
      message: result.text,
      steps: result.steps,  // All the tool calls made
      toolResults: result.toolResults,
      finishReason: result.finishReason
    }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
```

**Example execution trace:**
```
Step 1: AI calls getMessages({ days: 3 })
  → Returns: "Thursday soccer at 4pm... Friday birthday party at 2pm..."

Step 2: AI calls extractEvents({ text: "..." })
  → Returns: [{ day: "Thursday", time: "4pm" }, { day: "Friday", time: "2pm" }]

Step 3: AI calls checkCalendar({ date: "2025-01-16", time: "4pm" })
  → Returns: { hasConflict: true, events: [{ title: "Piano lesson" }] }

Step 4: AI calls createReminder({ title: "Resolve Thursday conflict", ... })
  → Returns: { success: true, reminderId: "uuid" }

Step 5: AI generates final response:
  "⚠️ I found a scheduling conflict on Thursday at 4pm. You have both soccer 
  practice and a piano lesson scheduled. I've created a reminder for you to 
  resolve this. I also noticed you haven't responded to the birthday party 
  RSVP for Friday."
Structured Output for Your UI
For your iOS app, you'll want structured responses:

typescript
// supabase/functions/proactive-scan/index.ts
import { generateObject } from 'npm:ai'  // ← Note: generateObject, not generateText
import { anthropic } from 'npm:@ai-sdk/anthropic'
import { z } from 'npm:zod'

Deno.serve(async (req) => {
  const { conversationId } = await req.json()
  
  // Get messages
  const { data: messages } = await supabase
    .from('messages')
    .select('content, created_at')
    .eq('conversation_id', conversationId)
    .gte('created_at', getDateDaysAgo(7))
  
  const messagesText = messages.map(m => m.content).join('\n')
  
  // Generate structured output
  const result = await generateObject({
    model: anthropic('claude-sonnet-4-20250514'),
    schema: z.object({
      conflicts: z.array(z.object({
        event1: z.string(),
        event2: z.string(),
        date: z.string(),
        severity: z.enum(['low', 'medium', 'high']),
        suggestion: z.string()
      })),
      pendingRSVPs: z.array(z.object({
        eventName: z.string(),
        requestedBy: z.string(),
        deadline: z.string().nullable(),
        urgent: z.boolean()
      })),
      upcomingDeadlines: z.array(z.object({
        task: z.string(),
        deadline: z.string(),
        daysUntil: z.number(),
        category: z.enum(['school', 'medical', 'activity', 'other'])
      })),
      recommendations: z.array(z.object({
        action: z.string(),
        priority: z.enum(['low', 'medium', 'high']),
        reason: z.string()
      }))
    }),
    messages: [
      {
        role: 'user',
        content: `Analyze these messages for scheduling issues, RSVPs, and deadlines:
        
        ${messagesText}`
      }
    ]
  })
  
  // result.object is guaranteed to match your schema
  return new Response(
    JSON.stringify(result.object),
    { headers: { 'Content-Type': 'application/json' } }
  )
})

function getDateDaysAgo(days: number): string {
  const date = new Date()
  date.setDate(date.getDate() - days)
  return date.toISOString()
}
From SwiftUI:

swift
// Models/ProactiveAnalysis.swift
struct ProactiveAnalysis: Codable {
    let conflicts: [ScheduleConflict]
    let pendingRSVPs: [PendingRSVP]
    let upcomingDeadlines: [Deadline]
    let recommendations: [Recommendation]
    
    struct ScheduleConflict: Codable {
        let event1: String
        let event2: String
        let date: String
        let severity: Severity
        let suggestion: String
        
        enum Severity: String, Codable {
            case low, medium, high
        }
    }
    
    struct PendingRSVP: Codable {
        let eventName: String
        let requestedBy: String
        let deadline: String?
        let urgent: Bool
    }
    
    struct Deadline: Codable {
        let task: String
        let deadline: String
        let daysUntil: Int
        let category: Category
        
        enum Category: String, Codable {
            case school, medical, activity, other
        }
    }
    
    struct Recommendation: Codable {
        let action: String
        let priority: Priority
        let reason: String
        
        enum Priority: String, Codable {
            case low, medium, high
        }
    }
}

// Services/ProactiveAssistantService.swift
func analyzeConversation(conversationId: UUID) async throws -> ProactiveAnalysis {
    let response = try await supabase.functions
        .invoke(
            "proactive-scan",
            options: FunctionInvokeOptions(
                body: ["conversationId": conversationId.uuidString]
            )
        )
    
    let decoder = JSONDecoder()
    return try decoder.decode(ProactiveAnalysis.self, from: response.data)
}
Database Schema for AI Features
sql
-- Calendar events extracted by AI
CREATE TABLE calendar_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  conversation_id UUID REFERENCES conversations(id),
  message_id UUID REFERENCES messages(id),
  title TEXT NOT NULL,
  date DATE NOT NULL,
  time TIME,
  location TEXT,
  extracted_at TIMESTAMP DEFAULT NOW(),
  confirmed BOOLEAN DEFAULT FALSE
);

-- RSVP tracking
CREATE TABLE rsvp_tracking (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  conversation_id UUID REFERENCES conversations(id),
  message_id UUID REFERENCES messages(id),
  event_name TEXT NOT NULL,
  requested_by UUID REFERENCES users(id),
  deadline TIMESTAMP,
  status TEXT DEFAULT 'pending', -- pending, responded, expired
  created_at TIMESTAMP DEFAULT NOW()
);

-- Reminders created by AI
CREATE TABLE reminders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  title TEXT NOT NULL,
  reminder_time TIMESTAMP NOT NULL,
  priority TEXT DEFAULT 'medium',
  status TEXT DEFAULT 'pending',
  created_by TEXT DEFAULT 'ai',
  created_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP
);

-- Decisions tracked
CREATE TABLE decisions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id),
  message_id UUID REFERENCES messages(id),
  decision_text TEXT NOT NULL,
  decided_by UUID REFERENCES users(id),
  category TEXT, -- carpool, activity, schedule, other
  created_at TIMESTAMP DEFAULT NOW()
);

-- Deadlines extracted
CREATE TABLE deadlines (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  conversation_id UUID REFERENCES conversations(id),
  message_id UUID REFERENCES messages(id),
  task TEXT NOT NULL,
  deadline TIMESTAMP NOT NULL,
  category TEXT, -- school, medical, activity, payment, other
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP
);

-- Indexes
CREATE INDEX idx_calendar_events_user_date ON calendar_events(user_id, date);
CREATE INDEX idx_rsvp_tracking_user_status ON rsvp_tracking(user_id, status);
CREATE INDEX idx_reminders_user_time ON reminders(user_id, reminder_time, status);
CREATE INDEX idx_deadlines_user_deadline ON deadlines(user_id, deadline, status);
4. Updated Implementation Timeline (Full-time with AI Assistance)
Teaching moment: With AI agents helping you code, you can move much faster. Here's an aggressive but achievable timeline:

Day 1 (Monday) - 8-10 hours
Morning (4 hours): Setup & Auth

 Create Supabase project
 Set up database schema (all tables)
 Create Xcode project (iOS 17+, SwiftUI)
 Install Supabase Swift SDK
 Build auth flow (login/signup)
 Test auth on device
Afternoon (4-6 hours): Basic Messaging

 Create message models
 Build ChatView UI
 Implement send/receive messages
 Add Realtime subscriptions
 Test real-time messaging between 2 devices
Evening Goal: Two phones can send messages back and forth in real-time

Day 2 (Tuesday) - 8-10 hours
Morning (4 hours): Offline Support & Persistence

 Set up SwiftData models
 Implement local message storage
 Build message sync service
 Add network monitoring
 Test offline → online sync
Afternoon (4-6 hours): Group Chat & Polish

 Add group conversation creation
 Implement group message attribution
 Add read receipts
 Build presence system (online/offline)
 Add typing indicators
Evening Goal: MVP is functionally complete. 3 devices can group chat with offline support.

Day 3 (Wednesday) - 8-10 hours
Morning (4 hours): Push Notifications

 Set up APNs certificates
 Implement push notification handling
 Test foreground/background notifications
 Add notification deep linking
Afternoon (4-6 hours): AI Setup & First Feature

 Set up OpenAI API keys in Supabase
 Create first Edge Function (calendar extraction)
 Test Edge Function from SwiftUI
 Build UI for calendar extraction feature
Evening Goal: Push notifications work. First AI feature (calendar extraction) is functional.

Day 4 (Thursday) - 8-10 hours
Morning (4 hours): Core AI Features (2-3)

 Build decision summarization Edge Function
 Implement priority message detection
 Create UIs for both features
 Test with real conversation data
Afternoon (4-6 hours): More AI Features (2)

 Build RSVP tracking Edge Function
 Implement deadline extraction
 Create tracking/reminder UIs
 Test end-to-end
Evening Goal: All 5 required AI features are working

Day 5 (Friday) - 8-10 hours
Full Day: Proactive Assistant (Advanced Feature)

 Design proactive assistant architecture
 Build multi-step agent Edge Function
 Implement tool calling (calendar check, conflict detection)
 Create proactive suggestion UI
 Build notification system for proactive alerts
 Test various scenarios
Evening Goal: Proactive assistant can detect conflicts and make suggestions

Day 6 (Saturday) - 6-8 hours
Morning (3-4 hours): Polish & Testing

 UI/UX refinements
 Error handling improvements
 Edge case testing
 Performance optimization
Afternoon (3-4 hours): Media Support

 Add image sending/receiving
 Implement Supabase Storage integration
 Add profile picture upload
 Test with various image sizes
Evening Goal: App feels polished and handles images

Day 7 (Sunday) - 6-8 hours
Morning (3-4 hours): Final Testing & Deployment

 Test all scenarios on physical devices
 Fix critical bugs
 Archive and upload to TestFlight
 Test TestFlight build
Afternoon (3-4 hours): Deliverables

 Record 5-7 minute demo video
 Write persona brainlift document
 Create GitHub repo with README
 Write social media post
 Final submission
Evening Goal: Everything submitted by 10:59 PM CT

5. Critical Success Factors for Full-Time Development
With AI Assistance:

Use Claude/Cursor to generate boilerplate
Ask AI to debug complex issues
Have AI write test scenarios
Use AI to explain Supabase/SwiftUI patterns you're unfamiliar with
Testing Strategy:

Test on physical devices DAILY
Keep 2-3 test devices handy
Test offline scenarios every afternoon
Don't wait until Day 7 to test on real hardware
Avoid These Pitfalls:

Don't over-engineer early - Get messaging working before making it perfect
Test incrementally - Don't build 3 features without testing the first one
Use AI, but understand the code - Don't blindly copy without knowing what it does
Start AI features early - Don't wait until Day 6 to test OpenAI integration
Next Steps
Want me to:

Create detailed Day 1 implementation guide - Step-by-step for auth + messaging?
Show complete Edge Function examples for all 5 required AI features?
Build SwiftUI component library - Reusable views you'll need?
Design the database migration strategy - SQL scripts in order?
What would be most helpful to start Day 1 strong?

provide a complete PRD doc


Orchestrated comprehensive PRD consolidating architecture, features, and specifications.


MessageAI - Product Requirements Document (PRD)
AI-Powered Messaging App for Busy Parents
Version: 1.0
Last Updated: October 20, 2025
Platform: iOS (SwiftUI)
Timeline: 7 Days (Full-time development)
Target: Busy Parents/Caregivers

Table of Contents
Product Vision
Target User & Persona
Technical Architecture
Core Messaging Features (MVP)
AI Features Implementation
Vercel AI SDK Integration
Database Schema
Implementation Timeline
Testing Strategy
Deployment
Success Criteria
File Structure
Environment Setup
1. Product Vision
Vision Statement
Build a production-quality iOS messaging application that combines WhatsApp-level reliability with intelligent AI features specifically designed to help busy parents manage family coordination, schedules, and decision-making.

Success Definition
A native iOS messaging app where:

Messages are never lost, even offline
Delivery is instant for online users
AI proactively helps with scheduling conflicts, RSVPs, and deadlines
Parents can coordinate family life without feeling overwhelmed
Inspiration
WhatsApp was built by two developers in months and scaled to billions. With modern AI tools and focused scope, a single developer can build something comparable in one week with features that genuinely solve real problems for a specific user group.

2. Target User & Persona
Persona: Busy Parent/Caregiver
Who They Are:

Parents juggling work and family responsibilities
Coordinators of children's activities (sports, school, playdates)
Members of multiple group chats (parent groups, family, carpool)
Time-strapped but need to stay on top of schedules
Core Pain Points:

Pain Point	Current Behavior	Desired Outcome
Schedule Juggling	Manually tracking multiple calendars, missing conflicts	Automatic conflict detection and resolution suggestions
Missing Important Dates	Scrolling through long threads to find deadlines	AI extracts and surfaces deadlines automatically
Decision Fatigue	Tracking what was decided across multiple chats	Clear decision log with context
RSVP Overload	Forgetting to respond to event invitations	Automatic RSVP tracking with reminders
Information Overload	Important messages buried in group chat noise	Priority messages highlighted automatically
User Goals:

Never miss a school deadline or permission slip
Avoid double-booking family activities
Know what decisions were made without re-reading threads
Respond to RSVPs on time
Coordinate carpools and activities efficiently
Device Context:

Primary device: iPhone (iOS 16+)
Uses phone throughout the day in short bursts
Often checking messages while multitasking
Needs quick glances to understand status
3. Technical Architecture
Technology Stack Overview
┌─────────────────────────────────────────────┐
│           iOS Application (Swift)            │
│                                              │
│  ┌────────────┐  ┌──────────────────────┐  │
│  │  SwiftUI   │  │  Swift Concurrency   │  │
│  │  (Views)   │  │   (async/await)      │  │
│  └────────────┘  └──────────────────────┘  │
│                                              │
│  ┌────────────┐  ┌──────────────────────┐  │
│  │ SwiftData  │  │  Supabase Swift SDK  │  │
│  │  (Local)   │  │   (Backend Client)   │  │
│  └────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────┘
                      ↓ URLSession
┌─────────────────────────────────────────────┐
│         Supabase Backend (Cloud)            │
│                                              │
│  ┌─────────────────┐  ┌──────────────────┐ │
│  │   PostgreSQL    │  │   Realtime       │ │
│  │   (Database)    │  │  (WebSockets)    │ │
│  └─────────────────┘  └──────────────────┘ │
│                                              │
│  ┌─────────────────┐  ┌──────────────────┐ │
│  │      Auth       │  │    Storage       │ │
│  │  (User Mgmt)    │  │  (Media Files)   │ │
│  └─────────────────┘  └──────────────────┘ │
│                                              │
│  ┌──────────────────────────────────────┐  │
│  │      Edge Functions (Deno)            │  │
│  │                                        │  │
│  │  ┌──────────────────────────────────┐ │  │
│  │  │     Vercel AI SDK (npm:ai)       │ │  │
│  │  │  - OpenAI API (GPT-4)            │ │  │
│  │  │  - Tool calling                   │ │  │
│  │  │  - Multi-step agents              │ │  │
│  │  └──────────────────────────────────┘ │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────┐
│            External Services                 │
│                                              │
│  OpenAI API (GPT-4)  │  Apple APNs          │
│  OpenAI Embeddings   │  (Push Notifications)│
└─────────────────────────────────────────────┘
Why This Architecture?
SwiftUI + Swift Concurrency:

Native iOS performance and feel
Modern async/await for clean async code
SwiftUI's declarative syntax for rapid UI development
Full access to iOS APIs (notifications, background modes)
Supabase for Backend:

PostgreSQL with real-time subscriptions (perfect for messaging)
Built-in authentication and user management
Row-level security for data privacy
Storage for media files
Edge Functions run close to database (low latency)
Vercel AI SDK in Supabase Edge Functions:

Best-in-class AI agent framework
Runs in Deno (Supabase Edge Functions runtime)
Co-located with database for fast data access
Tools/function calling for agentic behavior
Why Not Vercel Edge Functions?

Your database is on Supabase
AI agents need conversation history (requires DB access)
Supabase Edge Functions are co-located with your data
Eliminates network hop: Edge Function → DB vs Vercel → Internet → Supabase
Result: 50-200ms saved per AI request
Package Management in Deno
Teaching Moment: Supabase Edge Functions use Deno, not Node.js. Deno has different import syntax:

typescript
// ✅ Correct: npm packages (most common)
import { streamText, generateText, tool } from 'npm:ai@3.4.29'
import { openai } from 'npm:@ai-sdk/openai@1.0.5'
import { z } from 'npm:zod@3.22.4'

// ✅ Correct: JSR (Deno's native registry)
import { createClient } from 'jsr:@supabase/supabase-js@2'

// ✅ Correct: Direct URL imports
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

// ❌ Wrong: No npm install, no package.json
// Deno handles dependencies automatically
Why npm: prefix? Deno can import npm packages directly without installation. The first import caches the package.

4. Core Messaging Features (MVP)
4.1 Authentication & User Management
Requirements:

Email/password authentication via Supabase Auth
User profiles with display names and avatars
Session persistence across app launches
Secure token management
Database Schema:

sql
-- Users table (extends Supabase auth.users)
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP,
  status TEXT DEFAULT 'offline' -- online, offline, away
);

-- Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public profiles are viewable by everyone"
  ON users FOR SELECT
  USING (true);

CREATE POLICY "Users can update own profile"
  ON users FOR UPDATE
  USING (auth.uid() = id);
Swift Implementation:

swift
// Models/User.swift
import Foundation

struct User: Identifiable, Codable, Hashable {
    let id: UUID
    let email: String
    let username: String
    var displayName: String?
    var avatarUrl: String?
    let createdAt: Date
    var lastSeen: Date?
    var status: UserStatus
    
    enum UserStatus: String, Codable {
        case online, offline, away
    }
    
    enum CodingKeys: String, CodingKey {
        case id, email, username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case lastSeen = "last_seen"
        case status
    }
}

// ViewModels/AuthViewModel.swift
import Foundation
import Supabase

@MainActor
class AuthViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let supabase = SupabaseClient.shared.client
    
    init() {
        // Check for existing session
        Task {
            await checkSession()
        }
    }
    
    func checkSession() async {
        do {
            let session = try await supabase.auth.session
            if let userId = session.user.id {
                await fetchUserProfile(userId: userId)
            }
        } catch {
            isAuthenticated = false
        }
    }
    
    func signUp(email: String, password: String, username: String, displayName: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        
        do {
            let response = try await supabase.auth.signUp(
                email: email,
                password: password
            )
            
            guard let userId = response.user?.id else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user ID returned"])
            }
            
            // Create user profile
            let user = User(
                id: userId,
                email: email,
                username: username,
                displayName: displayName,
                avatarUrl: nil,
                createdAt: Date(),
                lastSeen: Date(),
                status: .online
            )
            
            try await supabase
                .from("users")
                .insert(user)
                .execute()
            
            self.currentUser = user
            self.isAuthenticated = true
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func signIn(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        
        do {
            let response = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            
            guard let userId = response.user.id else {
                throw NSError(domain: "Auth", code: -1)
            }
            
            await fetchUserProfile(userId: userId)
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func signOut() async {
        do {
            try await supabase.auth.signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func fetchUserProfile(userId: UUID) async {
        do {
            let user: User = try await supabase
                .from("users")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            
            self.currentUser = user
            self.isAuthenticated = true
            
            // Update last seen
            try? await supabase
                .from("users")
                .update(["last_seen": Date(), "status": "online"])
                .eq("id", value: userId)
                .execute()
            
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
UI Implementation:

swift
// Views/Auth/LoginView.swift
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Logo/Header
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("MessageAI")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Stay organized, never miss a thing")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 32)
                
                // Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .password
                        }
                    
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            Task { await authViewModel.signIn(email: email, password: password) }
                        }
                    
                    Button {
                        Task {
                            await authViewModel.signIn(email: email, password: password)
                        }
                    } label: {
                        HStack {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Sign In")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(email.isEmpty || password.isEmpty || authViewModel.isLoading)
                    
                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Spacer()
                
                // Sign up link
                NavigationLink {
                    SignUpView()
                } label: {
                    Text("Don't have an account? **Sign Up**")
                        .font(.subheadline)
                }
            }
            .padding()
        }
    }
}

// Views/Auth/SignUpView.swift
struct SignUpView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var username = ""
    @State private var displayName = ""
    
    var isValid: Bool {
        !email.isEmpty &&
        !password.isEmpty &&
        password == confirmPassword &&
        password.count >= 6 &&
        !username.isEmpty &&
        !displayName.isEmpty
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Create Account")
                    .font(.title)
                    .fontWeight(.bold)
                
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                    
                    TextField("Display Name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.name)
                    
                    SecureField("Password (min 6 characters)", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.newPassword)
                    
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.newPassword)
                    
                    if !password.isEmpty && password != confirmPassword {
                        Text("Passwords don't match")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Button {
                        Task {
                            await authViewModel.signUp(
                                email: email,
                                password: password,
                                username: username,
                                displayName: displayName
                            )
                            if authViewModel.isAuthenticated {
                                dismiss()
                            }
                        }
                    } label: {
                        Text("Create Account")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || authViewModel.isLoading)
                    
                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
4.2 One-on-One Chat
Database Schema:

sql
-- Conversations table
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT,
  avatar_url TEXT,
  is_group BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Conversation participants
CREATE TABLE conversation_participants (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMP DEFAULT NOW(),
  last_read_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (conversation_id, user_id)
);

-- Messages table
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  message_type TEXT DEFAULT 'text', -- text, image, system
  media_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP,
  local_id TEXT UNIQUE -- for optimistic UI
);

-- Typing indicators
CREATE TABLE typing_indicators (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  last_typed TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (conversation_id, user_id)
);

-- Row Level Security
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE typing_indicators ENABLE ROW LEVEL SECURITY;

-- Users can only see conversations they're part of
CREATE POLICY "Users can view own conversations"
  ON conversations FOR SELECT
  USING (
    id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create conversations"
  ON conversations FOR INSERT
  WITH CHECK (true);

-- Users can view participants in their conversations
CREATE POLICY "Users can view participants in own conversations"
  ON conversation_participants FOR SELECT
  USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can add participants to conversations"
  ON conversation_participants FOR INSERT
  WITH CHECK (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

-- Message policies
CREATE POLICY "Users can view messages in their conversations"
  ON messages FOR SELECT
  USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can send messages to their conversations"
  ON messages FOR INSERT
  WITH CHECK (
    sender_id = auth.uid() AND
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

-- Typing indicators
CREATE POLICY "Users can view typing in their conversations"
  ON typing_indicators FOR SELECT
  USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update own typing status"
  ON typing_indicators FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own typing status (update)"
  ON typing_indicators FOR UPDATE
  USING (user_id = auth.uid());

-- Indexes for performance
CREATE INDEX idx_messages_conversation_created ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_local_id ON messages(local_id);
CREATE INDEX idx_conversation_participants_user ON conversation_participants(user_id);
CREATE INDEX idx_conversation_participants_conversation ON conversation_participants(conversation_id);
CREATE INDEX idx_conversations_updated ON conversations(updated_at DESC);

-- Function to update conversation updated_at on new message
CREATE OR REPLACE FUNCTION update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE conversations
  SET updated_at = NEW.created_at
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_conversation_on_message
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_conversation_timestamp();
Swift Models:

swift
// Models/Conversation.swift
import Foundation

struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String?
    var avatarUrl: String?
    let isGroup: Bool
    let createdAt: Date
    var updatedAt: Date
    
    // Computed/joined data
    var participants: [User]?
    var lastMessage: Message?
    var unreadCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case avatarUrl = "avatar_url"
        case isGroup = "is_group"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case participants
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
    }
    
    // Display name logic
    func displayName(currentUserId: UUID) -> String {
        if let name = name {
            return name
        }
        
        // For 1-on-1, show other person's name
        if !isGroup, let other = participants?.first(where: { $0.id != currentUserId }) {
            return other.displayName ?? other.username
        }
        
        return "Chat"
    }
}

// Models/Message.swift
import Foundation

struct Message: Identifiable, Codable, Hashable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let content: String
    let messageType: MessageType
    var mediaUrl: String?
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var localId: String?
    
    // For display
    var sender: User?
    var status: MessageStatus = .sent
    
    enum MessageType: String, Codable {
        case text, image, system
    }
    
    enum MessageStatus: String, Codable {
        case sending, sent, delivered, read, failed
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case content
        case messageType = "message_type"
        case mediaUrl = "media_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case localId = "local_id"
        case sender
    }
    
    var isDeleted: Bool {
        deletedAt != nil
    }
}
Chat ViewModel:

swift
// ViewModels/ChatViewModel.swift
import Foundation
import Supabase
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var isSending = false
    @Published var typingUsers: Set<UUID> = []
    @Published var errorMessage: String?
    
    let conversation: Conversation
    let currentUserId: UUID
    
    private let supabase = SupabaseClient.shared.client
    private var realtimeChannel: RealtimeChannel?
    private var typingTimer: Timer?
    
    init(conversation: Conversation, currentUserId: UUID) {
        self.conversation = conversation
        self.currentUserId = currentUserId
    }
    
    func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let fetchedMessages: [Message] = try await supabase
                .from("messages")
                .select("""
                    *,
                    sender:users!sender_id(*)
                """)
                .eq("conversation_id", value: conversation.id)
                .is("deleted_at", value: "null")
                .order("created_at", ascending: true)
                .execute()
                .value
            
            self.messages = fetchedMessages
            
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }
    
    func sendMessage(content: String) async {
        guard !content.isEmpty else { return }
        
        isSending = true
        defer { isSending = false }
        
        let localId = UUID().uuidString
        let optimisticId = UUID()
        
        // Optimistic UI update
        let optimisticMessage = Message(
            id: optimisticId,
            conversationId: conversation.id,
            senderId: currentUserId,
            content: content,
            messageType: .text,
            createdAt: Date(),
            updatedAt: Date(),
            localId: localId,
            status: .sending
        )
        
        messages.append(optimisticMessage)
        
        do {
            // Insert into database
            let insertedMessage: Message = try await supabase
                .from("messages")
                .insert([
                    "conversation_id": conversation.id.uuidString,
                    "sender_id": currentUserId.uuidString,
                    "content": content,
                    "local_id": localId,
                    "message_type": "text"
                ])
                .select("""
                    *,
                    sender:users!sender_id(*)
                """)
                .single()
                .execute()
                .value
            
            // Replace optimistic message with real one
            if let index = messages.firstIndex(where: { $0.localId == localId }) {
                messages[index] = insertedMessage
                messages[index].status = .sent
            }
            
            // Clear typing indicator
            await clearTypingIndicator()
            
        } catch {
            // Mark message as failed
            if let index = messages.firstIndex(where: { $0.localId == localId }) {
                messages[index].status = .failed
            }
            errorMessage = "Failed to send message"
        }
    }
    
    func subscribeToMessages() {
        let channelName = "messages:\(conversation.id)"
        
        realtimeChannel = supabase
            .channel(channelName)
            .on(
                .postgresChanges(
                    event: .insert,
                    schema: "public",
                    table: "messages",
                    filter: "conversation_id=eq.\(conversation.id)"
                )
            ) { [weak self] payload in
                guard let self = self else { return }
                
                Task { @MainActor in
                    do {
                        // Decode the new message
                        let newMessage = try payload.decodeRecord() as Message
                        
                        // Only add if not from optimistic update
                        if !self.messages.contains(where: { $0.id == newMessage.id }) {
                            self.messages.append(newMessage)
                            
                            // Mark as delivered if from other user
                            if newMessage.senderId != self.currentUserId {
                                // Could update delivery status here
                            }
                        }
                    } catch {
                        print("Error decoding message: \(error)")
                    }
                }
            }
            .on(
                .postgresChanges(
                    event: .update,
                    schema: "public",
                    table: "typing_indicators",
                    filter: "conversation_id=eq.\(conversation.id)"
                )
            ) { [weak self] payload in
                // Handle typing indicators
                self?.handleTypingUpdate(payload)
            }
        
        Task {
            try? await realtimeChannel?.subscribe()
        }
    }
    
    func unsubscribe() {
        Task {
            try? await realtimeChannel?.unsubscribe()
        }
    }
    
    func setTyping() {
        Task {
            do {
                try await supabase
                    .from("typing_indicators")
                    .upsert([
                        "conversation_id": conversation.id.uuidString,
                        "user_id": currentUserId.uuidString,
                        "last_typed": Date().ISO8601Format()
                    ])
                    .execute()
            } catch {
                // Silently fail
            }
        }
        
        // Auto-clear after 3 seconds
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            Task { await self?.clearTypingIndicator() }
        }
    }
    
    private func clearTypingIndicator() async {
        do {
            try await supabase
                .from("typing_indicators")
                .delete()
                .eq("conversation_id", value: conversation.id)
                .eq("user_id", value: currentUserId)
                .execute()
        } catch {
            // Silently fail
        }
    }
    
    private func handleTypingUpdate(_ payload: RealtimePostgresChangesPayload) {
        // Parse typing indicator updates
        // Update typingUsers set
    }
    
    func retryFailedMessage(_ message: Message) async {
        guard message.status == .failed else { return }
        
        // Remove failed message
        messages.removeAll { $0.id == message.id }
        
        // Retry send
        await sendMessage(content: message.content)
    }
}
Chat View:

swift
// Views/Chat/ChatView.swift
import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var messageText = ""
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var isInputFocused: Bool
    
    init(conversation: Conversation, currentUserId: UUID) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(
            conversation: conversation,
            currentUserId: currentUserId
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageRow(
                                message: message,
                                isOwnMessage: message.senderId == viewModel.currentUserId
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom()
                }
            }
            
            // Typing indicator
            if !viewModel.typingUsers.isEmpty {
                HStack {
                    Text("Someone is typing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            
            Divider()
            
            // Input bar
            HStack(spacing: 12) {
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onChange(of: messageText) { _, newValue in
                        if !newValue.isEmpty {
                            viewModel.setTyping()
                        }
                    }
                
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty || viewModel.isSending)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle(viewModel.conversation.displayName(currentUserId: viewModel.currentUserId))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        // Show conversation info
                    } label: {
                        Label("Info", systemImage: "info.circle")
                    }
                    
                    Button(role: .destructive) {
                        // Leave conversation
                    } label: {
                        Label("Leave", systemImage: "arrow.right.square")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await viewModel.loadMessages()
            viewModel.subscribeToMessages()
        }
        .onDisappear {
            viewModel.unsubscribe()
        }
    }
    
    private func send() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        messageText = ""
        
        Task {
            await viewModel.sendMessage(content: text)
        }
    }
    
    private func scrollToBottom() {
        guard let lastMessage = viewModel.messages.last else { return }
        
        withAnimation {
            scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

// Views/Chat/MessageRow.swift
struct MessageRow: View {
    let message: Message
    let isOwnMessage: Bool
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwnMessage {
                Spacer(minLength: 60)
            } else {
                // Avatar
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(message.sender?.username.prefix(1).uppercased() ?? "?")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
            }
            
            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                // Message bubble
                Text(message.content)
                    .padding(12)
                    .background(isOwnMessage ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isOwnMessage ? .white : .primary)
                    .cornerRadius(16)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        
                        if isOwnMessage {
                            Button(role: .destructive) {
                                // Delete message
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                
                // Metadata
                HStack(spacing: 4) {
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if isOwnMessage {
                        statusIcon
                    }
                }
            }
            
            if !isOwnMessage {
                Spacer(minLength: 60)
            }
        }
    }
    
    @ViewBuilder
    var statusIcon: some View {
        switch message.status {
        case .sending:
            ProgressView()
                .scaleEffect(0.6)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .delivered:
            Image(systemName: "checkmark.checkmark")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .read:
            Image(systemName: "checkmark.checkmark")
                .font(.caption2)
                .foregroundColor(.blue)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }
}
4.3 Real-Time Messaging
Key Features:

WebSocket connection via Supabase Realtime
Instant message delivery to online users
Typing indicators
Presence tracking (online/offline)
Implementation: Already covered in ChatViewModel above with:

subscribeToMessages() - listens for new messages
setTyping() - broadcasts typing status
Optimistic UI updates
4.4 Offline Support & Local Persistence
Teaching Moment: SwiftData is Apple's modern persistence framework (iOS 17+). It saves data locally so your app works offline.

SwiftData Models:

swift
// Models/LocalMessage.swift
import SwiftData
import Foundation

@Model
final class LocalMessage {
    @Attribute(.unique) var id: String
    var conversationId: String
    var senderId: String
    var content: String
    var createdAt: Date
    var syncStatus: String // pending, synced, failed
    var localId: String?
    
    init(id: String, conversationId: String, senderId: String, content: String, createdAt: Date, syncStatus: String, localId: String? = nil) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.content = content
        self.createdAt = createdAt
        self.syncStatus = syncStatus
        self.localId = localId
    }
    
    enum SyncStatus: String {
        case pending, synced, failed
    }
}

@Model
final class LocalConversation {
    @Attribute(.unique) var id: String
    var name: String?
    var isGroup: Bool
    var createdAt: Date
    var lastSyncedAt: Date?
    
    init(id: String, name: String? = nil, isGroup: Bool, createdAt: Date) {
        self.id = id
        self.name = name
        self.isGroup = isGroup
        self.createdAt = createdAt
    }
}
Local Storage Service:

swift
// Services/LocalStorageService.swift
import SwiftData
import Foundation

@MainActor
class LocalStorageService {
    static let shared = LocalStorageService()
    
    private var container: ModelContainer
    private var context: ModelContext
    
    private init() {
        do {
            let schema = Schema([
                LocalMessage.self,
                LocalConversation.self
            ])
            
            container = try ModelContainer(for: schema)
            context = ModelContext(container)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }
    
    // MARK: - Messages
    
    func saveMessage(_ message: Message, syncStatus: LocalMessage.SyncStatus = .synced) throws {
        let localMessage = LocalMessage(
            id: message.id.uuidString,
            conversationId: message.conversationId.uuidString,
            senderId: message.senderId.uuidString,
            content: message.content,
            createdAt: message.createdAt,
            syncStatus: syncStatus.rawValue,
            localId: message.localId
        )
        
        context.insert(localMessage)
        try context.save()
    }
    
    func getMessages(forConversation conversationId: UUID) throws -> [LocalMessage] {
        let conversationIdString = conversationId.uuidString
        let descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate { $0.conversationId == conversationIdString },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        
        return try context.fetch(descriptor)
    }
    
    func getPendingMessages() throws -> [LocalMessage] {
        let descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate { $0.syncStatus == LocalMessage.SyncStatus.pending.rawValue }
        )
        
        return try context.fetch(descriptor)
    }
    
    func updateSyncStatus(localId: String, status: LocalMessage.SyncStatus) throws {
        let descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate { $0.localId == localId }
        )
        
        if let message = try context.fetch(descriptor).first {
            message.syncStatus = status.rawValue
            try context.save()
        }
    }
    
    func deleteMessage(id: UUID) throws {
        let idString = id.uuidString
        let descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate { $0.id == idString }
        )
        
        if let message = try context.fetch(descriptor).first {
            context.delete(message)
            try context.save()
        }
    }
    
    // MARK: - Conversations
    
    func saveConversation(_ conversation: Conversation) throws {
        let localConv = LocalConversation(
            id: conversation.id.uuidString,
            name: conversation.name,
            isGroup: conversation.isGroup,
            createdAt: conversation.createdAt
        )
        localConv.lastSyncedAt = Date()
        
        context.insert(localConv)
        try context.save()
    }
    
    func getConversations() throws -> [LocalConversation] {
        let descriptor = FetchDescriptor<LocalConversation>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        return try context.fetch(descriptor)
    }
}
Network Monitoring:

swift
// Utilities/NetworkMonitor.swift
import Network
import Combine

class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = true
    @Published var connectionType: NWInterface.InterfaceType?
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}
Message Sync Service:

swift
// Services/MessageSyncService.swift
import Foundation
import Combine

@MainActor
class MessageSyncService: ObservableObject {
    static let shared = MessageSyncService()
    
    @Published var isSyncing = false
    
    private let networkMonitor = NetworkMonitor()
    private let localStorage = LocalStorageService.shared
    private let supabase = SupabaseClient.shared.client
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Listen for network changes
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    Task {
                        await self?.syncPendingMessages()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func syncPendingMessages() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let pendingMessages = try localStorage.getPendingMessages()
            
            for localMessage in pendingMessages {
                do {
                    // Try to send to Supabase
                    let _: Message = try await supabase
                        .from("messages")
                        .insert([
                            "conversation_id": localMessage.conversationId,
                            "sender_id": localMessage.senderId,
                            "content": localMessage.content,
                            "local_id": localMessage.localId ?? "",
                            "created_at": localMessage.createdAt.ISO8601Format()
                        ])
                        .select()
                        .single()
                        .execute()
                        .value
                    
                    // Mark as synced
                    try localStorage.updateSyncStatus(
                        localId: localMessage.localId ?? "",
                        status: .synced
                    )
                    
                } catch {
                    // Mark as failed
                    try? localStorage.updateSyncStatus(
                        localId: localMessage.localId ?? "",
                        status: .failed
                    )
                    print("Failed to sync message: \(error)")
                }
            }
        } catch {
            print("Error getting pending messages: \(error)")
        }
    }
}
4.5 Group Chat
Database Schema: Already included above (conversations with is_group = true)

Group Creation:

swift
// Services/ConversationService.swift
import Foundation
import Supabase

@MainActor
class ConversationService {
    private let supabase = SupabaseClient.shared.client
    
    func createOneOnOneConversation(withUserId userId: UUID, currentUserId: UUID) async throws -> Conversation {
        // Check if conversation already exists
        let existing: [Conversation] = try await supabase
            .from("conversations")
            .select("""
                *,
                conversation_participants!inner(user_id)
            """)
            .eq("is_group", value: false)
            .filter("conversation_participants.user_id", operator: "in", value: "(\(currentUserId.uuidString),\(userId.uuidString))")
            .execute()
            .value
        
        // If exists, return it
        if let existingConv = existing.first {
            return existingConv
        }
        
        // Create new conversation
        let conversation: Conversation = try await supabase
            .from("conversations")
            .insert([
                "is_group": false
            ])
            .select()
            .single()
            .execute()
            .value
        
        // Add participants
        try await supabase
            .from("conversation_participants")
            .insert([
                ["conversation_id": conversation.id.uuidString, "user_id": currentUserId.uuidString],
                ["conversation_id": conversation.id.uuidString, "user_id": userId.uuidString]
            ])
            .execute()
        
        return conversation
    }
    
    func createGroupConversation(name: String, participantIds: [UUID], creatorId: UUID) async throws -> Conversation {
        // Create conversation
        let conversation: Conversation = try await supabase
            .from("conversations")
            .insert([
                "name": name,
                "is_group": true
            ])
            .select()
            .single()
            .execute()
            .value
        
        // Add all participants (including creator)
        var allParticipants = participantIds
        if !allParticipants.contains(creatorId) {
            allParticipants.append(creatorId)
        }
        
        let participants = allParticipants.map { userId in
            [
                "conversation_id": conversation.id.uuidString,
                "user_id": userId.uuidString
            ]
        }
        
        try await supabase
            .from("conversation_participants")
            .insert(participants)
            .execute()
        
        return conversation
    }
    
    func addParticipant(userId: UUID, toConversation conversationId: UUID) async throws {
        try await supabase
            .from("conversation_participants")
            .insert([
                "conversation_id": conversationId.uuidString,
                "user_id": userId.uuidString
            ])
            .execute()
    }
    
    func removeParticipant(userId: UUID, fromConversation conversationId: UUID) async throws {
        try await supabase
            .from("conversation_participants")
            .delete()
            .eq("conversation_id", value: conversationId)
            .eq("user_id", value: userId)
            .execute()
    }
}
4.6 Read Receipts
Database Schema:

sql
-- Read receipts table
CREATE TABLE read_receipts (
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  read_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);

ALTER TABLE read_receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view read receipts in their conversations"
  ON read_receipts FOR SELECT
  USING (
    message_id IN (
      SELECT id FROM messages WHERE conversation_id IN (
        SELECT conversation_id FROM conversation_participants
        WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Users can insert own read receipts"
  ON read_receipts FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE INDEX idx_read_receipts_message ON read_receipts(message_id);
CREATE INDEX idx_read_receipts_user ON read_receipts(user_id);
Implementation:

swift
// Add to ChatViewModel
func markAsRead(messageId: UUID) async {
    do {
        try await supabase
            .from("read_receipts")
            .insert([
                "message_id": messageId.uuidString,
                "user_id": currentUserId.uuidString
            ])
            .execute()
        
        // Update last_read_at in conversation_participants
        try await supabase
            .from("conversation_participants")
            .update(["last_read_at": Date().ISO8601Format()])
            .eq("conversation_id", value: conversation.id)
            .eq("user_id", value: currentUserId)
            .execute()
        
    } catch {
        // Silently fail
    }
}

// Mark messages as read when view appears
func markAllAsRead() async {
    guard let lastMessage = messages.last else { return }
    await markAsRead(messageId: lastMessage.id)
}
4.7 Push Notifications
Setup in Xcode:

Enable "Push Notifications" capability
Enable "Background Modes" → "Remote notifications"
APNs Configuration:

swift
// App/MessageAIApp.swift
import SwiftUI
import UserNotifications

@main
struct MessageAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var networkMonitor = NetworkMonitor()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(networkMonitor)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Request notification permissions
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        
        return true
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("Device token: \(token)")
        
        // Save to user profile
        Task {
            guard let userId = try? await SupabaseClient.shared.client.auth.session.user.id else {
                return
            }
            
            try? await SupabaseClient.shared.client
                .from("users")
                .update(["push_token": token])
                .eq("id", value: userId)
                .execute()
        }
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Failed to register for remote notifications: \(error)")
    }
    
    // Handle notifications when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification taps
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Deep link to conversation
        if let conversationId = userInfo["conversationId"] as? String {
            NotificationCenter.default.post(
                name: .openConversation,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
        }
        
        completionHandler()
    }
}

// Notification name for deep linking
extension Notification.Name {
    static let openConversation = Notification.Name("openConversation")
}
Database Schema for Push Tokens:

sql
-- Add push_token to users table
ALTER TABLE users ADD COLUMN push_token TEXT;

CREATE INDEX idx_users_push_token ON users(push_token);
Edge Function for Sending Notifications:

typescript
// supabase/functions/send-notification/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const { userId, title, body, conversationId } = await req.json()
    
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, // Service role for admin access
    )
    
    // Get user's push token
    const { data: user } = await supabase
      .from('users')
      .select('push_token')
      .eq('id', userId)
      .single()
    
    if (!user?.push_token) {
      return new Response(JSON.stringify({ error: 'No push token' }), {
        status: 400
      })
    }
    
    // Send to APNs
    const apnsResponse = await fetch(
      `https://api.push.apple.com/3/device/${user.push_token}`,
      {
        method: 'POST',
        headers: {
          'apns-topic': 'com.yourapp.messageai', // Your bundle ID
          'apns-priority': '10',
          'authorization': `bearer ${Deno.env.get('APNS_KEY')}`, // APNs JWT token
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          aps: {
            alert: {
              title,
              body
            },
            sound: 'default',
            badge: 1,
            'mutable-content': 1
          },
          conversationId
        })
      }
    )
    
    if (!apnsResponse.ok) {
      const error = await apnsResponse.text()
      throw new Error(`APNs error: ${error}`)
    }
    
    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' }
    })
    
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    })
  }
})
Database Trigger to Send Notifications:

sql
-- Function to send notification on new message
CREATE OR REPLACE FUNCTION notify_new_message()
RETURNS TRIGGER AS $$
DECLARE
  participant RECORD;
BEGIN
  -- For each participant except the sender
  FOR participant IN
    SELECT user_id
    FROM conversation_participants
    WHERE conversation_id = NEW.conversation_id
      AND user_id != NEW.sender_id
  LOOP
    -- Call edge function to send push notification
    PERFORM net.http_post(
      url := 'https://your-project.supabase.co/functions/v1/send-notification',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'userId', participant.user_id,
        'title', 'New message',
        'body', LEFT(NEW.content, 100),
        'conversationId', NEW.conversation_id
      )
    );
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_notify_new_message
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_new_message();
5. AI Features Implementation
Overview of AI Features for Busy Parent/Caregiver Persona
All AI features are implemented as Supabase Edge Functions using the Vercel AI SDK. Each feature:

Uses OpenAI GPT-4 for intelligence
Has direct access to Supabase database (low latency)
Returns structured JSON for easy iOS integration
Handles errors gracefully
5.1 Smart Calendar Extraction
Purpose: Automatically detect dates, times, and events in messages and suggest adding them to calendar.

Edge Function:

typescript
// supabase/functions/extract-calendar-events/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { generateObject } from 'npm:ai@3.4.29'
import { openai } from 'npm:@ai-sdk/openai@1.0.5'
import { z } from 'npm:zod@3.22.4'
import { createClient } from 'jsr:@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response('Unauthorized', { status: 401 })
    }
    
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    
    const { conversationId, messageIds } = await req.json()
    
    // Fetch messages
    const { data: messages, error } = await supabase
      .from('messages')
      .select('id, content, created_at, sender:users(display_name)')
      .eq('conversation_id', conversationId)
      .in('id', messageIds || [])
      .order('created_at', { ascending: true })
    
    if (error) throw error
    
    const messagesText = messages
      .map(m => `[${m.created_at}] ${m.sender.display_name}: ${m.content}`)
      .join('\n')
    
    // Extract events using AI
    const result = await generateObject({
      model: openai('gpt-4o'),
      schema: z.object({
        events: z.array(z.object({
          title: z.string().describe('Brief event title'),
          date: z.string().describe('Date in YYYY-MM-DD format'),
          time: z.string().nullable().describe('Time in HH:MM format (24-hour) or null if not specified'),
          location: z.string().nullable().describe('Location or null if not mentioned'),
          description: z.string().describe('Additional details about the event'),
          category: z.enum(['school', 'medical', 'activity', 'social', 'other']),
          confidence: z.number().min(0).max(1).describe('Confidence score 0-1'),
          sourceMessageId: z.string().describe('ID of the message this came from')
        }))
      }),
      messages: [
        {
          role: 'system',
          content: `You are an assistant that extracts calendar events from parent group chat messages.
          
          Extract:
          - School events (field trips, picture day, parent-teacher conferences)
          - Medical appointments
          - Children's activities (soccer practice, dance class, birthday parties)
          - Social events (playdates, carpools)
          
          Important:
          - Only extract events with clear dates
          - Today is ${new Date().toISOString().split('T')[0]}
          - Convert relative dates (tomorrow, next Tuesday) to absolute dates
          - Be conservative - only extract if you're confident
          - Provide the message ID for each event`
        },
        {
          role: 'user',
          content: `Extract calendar events from these messages:\n\n${messagesText}`
        }
      ]
    })
    
    // Store events in database
    for (const event of result.object.events) {
      if (event.confidence >= 0.7) { // Only store high-confidence events
        await supabase
          .from('calendar_events')
          .insert({
            conversation_id: conversationId,
            message_id: event.sourceMessageId,
            title: event.title,
            date: event.date,
            time: event.time,
            location: event.location,
            description: event.description,
            category: event.category,
            confidence: event.confidence,
            confirmed: false
          })
      }
    }
    
    return new Response(
      JSON.stringify({ events: result.object.events }),
      { headers: { 'Content-Type': 'application/json' } }
    )
    
  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
Database Schema:

sql
CREATE TABLE calendar_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  date DATE NOT NULL,
  time TIME,
  location TEXT,
  description TEXT,
  category TEXT NOT NULL, -- school, medical, activity, social, other
  confidence FLOAT NOT NULL,
  confirmed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_calendar_events_conversation ON calendar_events(conversation_id);
CREATE INDEX idx_calendar_events_date ON calendar_events(date);
CREATE INDEX idx_calendar_events_confirmed ON calendar_events(confirmed);
Swift Integration:

swift
// Models/CalendarEvent.swift
struct CalendarEvent: Identifiable, Codable {
    let id: UUID
    let conversationId: UUID
    let messageId: UUID
    let title: String
    let date: Date
    let time: Date?
    let location: String?
    let description: String
    let category: Category
    let confidence: Double
    var confirmed: Bool
    let createdAt: Date
    
    enum Category: String, Codable {
        case school, medical, activity, social, other
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case title, date, time, location, description, category, confidence, confirmed
        case createdAt = "created_at"
    }
    
    var categoryIcon: String {
        switch category {
        case .school: return "graduationcap.fill"
        case .medical: return "cross.case.fill"
        case .activity: return "figure.run"
        case .social: return "person.2.fill"
        case .other: return "calendar"
        }
    }
    
    var categoryColor: Color {
        switch category {
        case .school: return .blue
        case .medical: return .red
        case .activity: return .green
        case .social: return .purple
        case .other: return .gray
        }
    }
}

// Services/AIService.swift
extension AIService {
    func extractCalendarEvents(conversationId: UUID, messageIds: [UUID]? = nil) async throws -> [CalendarEvent] {
        let response = try await supabase.functions
            .invoke(
                "extract-calendar-events",
                options: FunctionInvokeOptions(
                    body: [
                        "conversationId": conversationId.uuidString,
                        "messageIds": messageIds?.map { $0.uuidString }
                    ]
                )
            )
        
        struct Response: Codable {
            let events: [CalendarEvent]
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(Response.self, from: response.data)
        return result.events
    }
    
    func confirmCalendarEvent(eventId: UUID) async throws {
        try await supabase
            .from("calendar_events")
            .update(["confirmed": true])
            .eq("id", value: eventId)
            .execute()
    }
}
UI View:

swift
// Views/AI/CalendarEventsView.swift
struct CalendarEventsView: View {
    let conversationId: UUID
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = false
    @State private var error: String?
    
    private let aiService = AIService()
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Scanning messages for events...")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section {
                ForEach(events) { event in
                    CalendarEventRow(event: event) {
                        Task {
                            try? await aiService.confirmCalendarEvent(eventId: event.id)
                            if let index = events.firstIndex(where: { $0.id == event.id }) {
                                events[index].confirmed = true
                            }
                        }
                    }
                }
            } header: {
                Text("Detected Events")
            } footer: {
                if !events.isEmpty {
                    Text("Tap to add to your calendar")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Calendar Events")
        .toolbar {
            Button {
                Task { await extractEvents() }
            } label: {
                Label("Scan", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
        .task {
            await loadEvents()
        }
    }
    
    func loadEvents() async {
        // Load already extracted events from DB
        do {
            events = try await supabase
                .from("calendar_events")
                .select()
                .eq("conversation_id", value: conversationId)
                .order("date", ascending: true)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func extractEvents() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let newEvents = try await aiService.extractCalendarEvents(conversationId: conversationId)
            events = newEvents
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CalendarEventRow: View {
    let event: CalendarEvent
    let onConfirm: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: event.categoryIcon)
                .font(.title2)
                .foregroundColor(event.categoryColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Label(event.date, style: .date)
                    
                    if let time = event.time {
                        Label(time, style: .time)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                
                if let location = event.location {
                    Label(location, systemImage: "location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if !event.confirmed {
                    Text("Confidence: \(Int(event.confidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            if event.confirmed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button {
                    onConfirm()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
5.2 Decision Summarization
Purpose: Track decisions made in group chats so parents don't have to re-read entire threads.

Edge Function:

typescript
// supabase/functions/track-decisions/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { generateObject } from 'npm:ai@3.4.29'
import { openai } from 'npm:@ai-sdk/openai@1.0.5'
import { z } from 'npm:zod@3.22.4'
import { createClient } from 'jsr:@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response('Unauthorized', { status: 401 })
    }
    
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    
    const { conversationId, daysBack = 7 } = await req.json()
    
    const since = new Date()
    since.setDate(since.getDate() - daysBack)
    
    // Fetch recent messages
    const { data: messages } = await supabase
      .from('messages')
      .select('id, content, created_at, sender:users(id, display_name)')
      .eq('conversation_id', conversationId)
      .gte('created_at', since.toISOString())
      .order('created_at', { ascending: true })
    
    const messagesText = messages
      .map(m => `[${m.id}] ${m.sender.display_name}: ${m.content}`)
      .join('\n')
    
    // Extract decisions
    const result = await generateObject({
      model: openai('gpt-4o'),
      schema: z.object({
        decisions: z.array(z.object({
          messageId: z.string(),
          decision: z.string().describe('Clear statement of what was decided'),
          category: z.enum(['carpool', 'activity', 'schedule', 'purchase', 'food', 'other']),
          participants: z.array(z.string()).describe('Names of people involved in decision'),
          deadline: z.string().nullable().describe('Deadline if mentioned (YYYY-MM-DD)'),
          confidence: z.number().min(0).max(1)
        }))
      }),
      messages: [
        {
          role: 'system',
          content: `Extract decisions from parent group chat messages.
          
          A decision is:
          - A clear agreement or choice made by the group
          - Examples: "Let's do pizza Friday", "I'll drive carpool Tuesday", "Meeting at 3pm works"
          
          Look for:
          - Explicit agreements ("sounds good", "let's do it", "agreed")
          - Plans with consensus
          - Assignments ("I'll do X", "You handle Y")
          
          Ignore:
          - Questions or proposals without consensus
          - Individual opinions without agreement
          - Tentative suggestions`
        },
        {
          role: 'user',
          content: `Extract decisions from:\n\n${messagesText}`
        }
      ]
    })
    
    // Store decisions
    for (const decision of result.object.decisions) {
      if (decision.confidence >= 0.7) {
        const message = messages.find(m => m.id === decision.messageId)
        if (message) {
          await supabase
            .from('decisions')
            .insert({
              conversation_id: conversationId,
              message_id: decision.messageId,
              decision_text: decision.decision,
              category: decision.category,
              decided_by: message.sender.id,
              deadline: decision.deadline,
              created_at: message.created_at
            })
        }
      }
    }
    
    return new Response(
      JSON.stringify({ decisions: result.object.decisions }),
      { headers: { 'Content-Type': 'application/json' } }
    )
    
  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
Database Schema:

sql
CREATE TABLE decisions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  decision_text TEXT NOT NULL,
  category TEXT NOT NULL,
  decided_by UUID REFERENCES users(id),
  deadline DATE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_decisions_conversation ON decisions(conversation_id);
CREATE INDEX idx_decisions_deadline ON decisions(deadline);
5.3 Priority Message Highlighting
Purpose: Automatically flag messages that need immediate attention (school closures, RSVP requests, urgent questions).

Edge Function:

typescript
// supabase/functions/detect-priority/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { generateObject } from 'npm:ai@3.4.29'
import { openai } from 'npm:@ai-sdk/openai@1.0.5'
import { z } from 'npm:zod@3.22.4'
import { createClient } from 'jsr:@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const authHeader = req.headers.get('Authorization')
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    
    const { conversationId } = await req.json()
    
    // Get recent unread messages
    const { data: messages } = await supabase
      .from('messages')
      .select('id, content, created_at, sender:users(display_name)')
      .eq('conversation_id', conversationId)
      .gte('created_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
      .order('created_at', { ascending: false })
      .limit(50)
    
    const messagesText = messages
      .map(m => `[${m.id}] ${m.sender.display_name}: ${m.content}`)
      .join('\n')
    
    const result = await generateObject({
      model: openai('gpt-4o'),
      schema: z.object({
        priorityMessages: z.array(z.object({
          messageId: z.string(),
          priority: z.enum(['urgent', 'high', 'medium']),
          reason: z.string().describe('Why this message is priority'),
          actionRequired: z.boolean().describe('Does this need a response/action?')
        }))
      }),
      messages: [
        {
          role: 'system',
          content: `Identify priority messages in parent group chat.
          
          URGENT priority:
          - School emergencies or closures
          - Last-minute changes to pick-up times
          - Safety concerns
          - Time-sensitive requests expiring soon
          
          HIGH priority:
          - RSVP requests with deadlines
          - Permission slips due soon
          - Direct questions to the user
          - Schedule conflicts
          - Important school announcements
          
          MEDIUM priority:
          - General reminders
          - Upcoming events (not urgent)
          - FYI information that's useful
          
          Not priority:
          - General chat/social
          - Already resolved issues
          - Old information`
        },
        {
          role: 'user',
          content: `Analyze these messages:\n\n${messagesText}`
        }
      ]
    })
    
    // Store priority flags
    for (const pm of result.object.priorityMessages) {
      await supabase
        .from('priority_messages')
        .upsert({
          message_id: pm.messageId,
          priority: pm.priority,
          reason: pm.reason,
          action_required: pm.actionRequired
        })
    }
    
    return new Response(
      JSON.stringify({ priorityMessages: result.object.priorityMessages }),
      { headers: { 'Content-Type': 'application/json' } }
    )
    
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
Database Schema:

sql
CREATE TABLE priority_messages (
  message_id UUID PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
  priority TEXT NOT NULL, -- urgent, high, medium
  reason TEXT NOT NULL,
  action_required BOOLEAN DEFAULT FALSE,
  dismissed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_priority_messages_priority ON priority_messages(priority);
CREATE INDEX idx_priority_messages_dismissed ON priority_messages(dismissed);
5.4 RSVP Tracking
Purpose: Automatically detect RSVP requests and track who responded.

Edge Function:

typescript
// supabase/functions/track-rsvps/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { generateObject } from 'npm:ai@3.4.29'
import { openai } from 'npm:@ai-sdk/openai@1.0.5'
import { z } from 'npm:zod@3.22.4'
import { createClient } from 'jsr:@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const authHeader = req.headers.get('Authorization')
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    
    const { conversationId, userId } = await req.json()
    
    const { data: messages } = await supabase
      .from('messages')
      .select('id, content, created_at, sender:users(id, display_name)')
      .eq('conversation_id', conversationId)
      .gte('created_at', new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString())
      .order('created_at', { ascending: true })
    
    const messagesText = messages
      .map(m => `[${m.id}] ${m.sender.display_name}: ${m.content}`)
      .join('\n')
    
    const result = await generateObject({
      model: openai('gpt-4o'),
      schema: z.object({
        rsvps: z.array(z.object({
          messageId: z.string().describe('ID of message with RSVP request'),
          eventName: z.string().describe('Name of the event'),
          requestedBy: z.string().describe('Who requested the RSVP'),
          deadline: z.string().nullable().describe('RSVP deadline (YYYY-MM-DD)'),
          eventDate: z.string().describe('Date of event (YYYY-MM-DD)'),
          responses: z.array(z.object({
            person: z.string(),
            response: z.enum(['yes', 'no', 'maybe']),
            messageId: z.string()
          })).describe('Who responded and how')
        }))
      }),
      messages: [
        {
          role: 'system',
          content: `Extract RSVP requests and track responses from parent messages.
          
          RSVP request patterns:
          - "Can you come to..."
          - "Please let me know if..."
          - "RSVP by Friday"
          - "Who's coming to..."
          
          Response patterns:
          - "We'll be there"
          - "Can't make it"
          - "Count us in"
          - "Sorry, we have plans"
          
          Track both requests and responses.`
        },
        {
          role: 'user',
          content: `Extract RSVPs:\n\n${messagesText}`
        }
      ]
    })
    
    // Store RSVPs
    for (const rsvp of result.object.rsvps) {
      const requestMessage = messages.find(m => m.id === rsvp.messageId)
      
      // Check if user has responded
      const userResponded = rsvp.responses.some(r => 
        messages.find(m => m.id === r.messageId)?.sender.id === userId
      )
      
      await supabase
        .from('rsvp_tracking')
        .upsert({
          message_id: rsvp.messageId,
          conversation_id: conversationId,
          user_id: userId,
          event_name: rsvp.eventName,
          requested_by: requestMessage?.sender.id,
          deadline: rsvp.deadline,
          event_date: rsvp.eventDate,
          status: userResponded ? 'responded' : 'pending',
          response: userResponded ? 
            rsvp.responses.find(r => messages.find(m => m.id === r.messageId)?.sender.id === userId)?.response :
            null
        }, {
          onConflict: 'message_id,user_id'
        })
    }
    
    return new Response(
      JSON.stringify({ rsvps: result.object.rsvps }),
      { headers: { 'Content-Type': 'application/json' } }
    )
    
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
Database Schema:

sql
CREATE TABLE rsvp_tracking (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  event_name TEXT NOT NULL,
  requested_by UUID REFERENCES users(id),
  deadline DATE,
  event_date DATE NOT NULL,
  status TEXT DEFAULT 'pending', -- pending, responded, expired
  response TEXT, -- yes, no, maybe
  created_at TIMESTAMP DEFAULT NOW(),
  responded_at TIMESTAMP,
  UNIQUE(message_id, user_id)
);

CREATE INDEX idx_rsvp_tracking_user_status ON rsvp_tracking(user_id, status);
CREATE INDEX idx_rsvp_tracking_deadline ON rsvp_tracking(deadline);
5.5 Deadline/Reminder Extraction
Purpose: Extract deadlines from messages and create reminders automatically.

Edge Function:

typescript
// supabase/functions/extract-deadlines/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { generateObject } from 'npm:ai@3.4.29'
import { openai } from 'npm:@ai-sdk/openai@1.0.5'
import { z } from 'npm:zod@3.22.4'
import { createClient } from 'jsr:@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const authHeader = req.headers.get('Authorization')
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    
    const { conversationId, userId } = await req.json()
    
    const { data: messages } = await supabase
      .from('messages')
      .select('id, content, created_at')
      .eq('conversation_id', conversationId)
      .gte('created_at', new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString())
      .order('created_at', { ascending: true })
    
    const messagesText = messages
      .map(m => `[${m.id}] ${m.content}`)
      .join('\n')
    
    const result = await generateObject({
      model: openai('gpt-4o'),
      schema: z.object({
        deadlines: z.array(z.object({
          messageId: z.string(),
          task: z.string().describe('What needs to be done'),
          deadline: z.string().describe('Deadline date (YYYY-MM-DD)'),
          category: z.enum(['school', 'medical', 'activity', 'payment', 'other']),
          priority: z.enum(['low', 'medium', 'high', 'urgent']),
          details: z.string().describe('Additional context')
        }))
      }),
      messages: [
        {
          role: 'system',
          content: `Extract deadlines and tasks from parent messages.
          
          Today is ${new Date().toISOString().split('T')[0]}
          
          Look for:
          - Permission slips due dates
          - School forms deadlines
          - Payment due dates
          - Registration closing dates
          - RSVP deadlines
          - Appointment scheduling windows
          
          Deadline phrases:
          - "due by Friday"
          - "must submit by..."
          - "deadline is..."
          - "no later than..."
          - "before Monday"
          
          Convert relative dates to absolute dates.
          Prioritize based on urgency (how soon is deadline).`
        },
        {
          role: 'user',
          content: `Extract deadlines:\n\n${messagesText}`
        }
      ]
    })
    
    // Store deadlines
    for (const deadline of result.object.deadlines) {
      await supabase
        .from('deadlines')
        .insert({
          message_id: deadline.messageId,
          conversation_id: conversationId,
          user_id: userId,
          task: deadline.task,
          deadline: deadline.deadline,
          category: deadline.category,
          priority: deadline.priority,
          details: deadline.details,
          status: 'pending'
        })
      
      // Create reminder (day before deadline)
      const deadlineDate = new Date(deadline.deadline)
      const reminderDate = new Date(deadlineDate)
      reminderDate.setDate(reminderDate.getDate() - 1)
      reminderDate.setHours(18, 0, 0, 0) // 6 PM day before
      
      if (reminderDate > new Date()) {
        await supabase
          .from('reminders')
          .insert({
            user_id: userId,
            title: `Reminder: ${deadline.task}`,
            reminder_time: reminderDate.toISOString(),
            priority: deadline.priority,
            status: 'pending',
            created_by: 'ai'
          })
      }
    }
    
    return new Response(
      JSON.stringify({ deadlines: result.object.deadlines }),
      { headers: { 'Content-Type': 'application/json' } }
    )
    
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
Database Schema:

sql
CREATE TABLE deadlines (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  task TEXT NOT NULL,
  deadline DATE NOT NULL,
  category TEXT NOT NULL,
  priority TEXT NOT NULL,
  details TEXT,
  status TEXT DEFAULT 'pending', -- pending, completed, expired
  created_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP
);

CREATE TABLE reminders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  reminder_time TIMESTAMP NOT NULL,
  priority TEXT DEFAULT 'medium',
  status TEXT DEFAULT 'pending', -- pending, sent, dismissed
  created_by TEXT DEFAULT 'user', -- user or ai
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_deadlines_user_status ON deadlines(user_id, status, deadline);
CREATE INDEX idx_reminders_user_time ON reminders(user_id, reminder_time, status);
6. Vercel AI SDK Integration
Advanced Feature: Proactive Assistant
Purpose: Multi-step AI agent that proactively detects issues and suggests solutions without being asked.

Key Capabilities:

Detects scheduling conflicts automatically
Suggests carpool opportunities
Reminds about pending RSVPs
Alerts about approaching deadlines
Offers to create calendar events
How It Works
Teaching Moment: The Vercel AI SDK's "tools" feature (also called function calling) lets your AI agent:

Decide which functions to call
Execute those functions
Use the results to make decisions
Take multiple steps to complete a task
This is different from simple chat - the agent can actually DO things.

Multi-Step Agent with Tools
typescript
// supabase/functions/proactive-assistant/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { generateText, tool } from 'npm:ai@3.4.29'
import { openai } from 'npm:@ai-sdk/openai@1.0.5'
import { z } from 'npm:zod@3.22.4'
import { createClient } from 'jsr:@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const authHeader = req.headers.get('Authorization')
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    
    const { conversationId, userId } = await req.json()
    
    // Multi-step agent that can use tools
    const result = await generateText({
      model: openai('gpt-4o'),
      maxTokens: 4000,
      maxSteps: 5, // Agent can use tools up to 5 times
      
      system: `You are a proactive scheduling assistant for busy parents.
      
      Your job is to:
      1. Check recent messages for scheduling information
      2. Look for conflicts with existing calendar events
      3. Identify missed RSVPs or approaching deadlines
      4. Provide specific, actionable recommendations
      
      Be proactive but not overwhelming. Focus on the top 1-2 most important issues.
      
      Today is ${new Date().toISOString().split('T')[0]}`,
      
      messages: [
        {
          role: 'user',
          content: 'Check if there are any scheduling issues or things I need to handle.'
        }
      ],
      
      tools: {
        // Tool 1: Get recent messages
        getRecentMessages: tool({
          description: 'Retrieve recent messages from the conversation',
          parameters: z.object({
            days: z.number().describe('Number of days of message history to retrieve')
          }),
          execute: async ({ days }) => {
            const since = new Date()
            since.setDate(since.getDate() - days)
            
            const { data: messages } = await supabase
              .from('messages')
              .select('content, created_at, sender:users(display_name)')
              .eq('conversation_id', conversationId)
              .gte('created_at', since.toISOString())
              .order('created_at', { ascending: true })
            
            return messages?.map(m =>
              `[${m.created_at}] ${m.sender.display_name}: ${m.content}`
            ).join('\n') || ''
          }
        }),
        
        // Tool 2: Get user's calendar events
        getCalendarEvents: tool({
          description: 'Get calendar events for the user',
          parameters: z.object({
            daysAhead: z.number().describe('How many days ahead to look')
          }),
          execute: async ({ daysAhead }) => {
            const endDate = new Date()
            endDate.setDate(endDate.getDate() + daysAhead)
            
            const { data: events } = await supabase
              .from('calendar_events')
              .select('*')
              .eq('user_id', value: userId) // Note: Need to join or filter properly
              .gte('date', new Date().toISOString().split('T')[0])
              .lte('date', endDate.toISOString().split('T')[0])
              .order('date', { ascending: true })
            
            return events || []
          }
        }),
        
        // Tool 3: Check for schedule conflicts
        checkConflicts: tool({
          description: 'Check if two events conflict',
          parameters: z.object({
            event1: z.object({
              title: z.string(),
              date: z.string(),
              time: z.string().nullable()
            }),
            event2: z.object({
              title: z.string(),
              date: z.string(),
              time: z.string().nullable()
            })
          }),
          execute: async ({ event1, event2 }) => {
            // Simple conflict check
            if (event1.date !== event2.date) {
              return { hasConflict: false }
            }
            
            if (!event1.time || !event2.time) {
              return {
                hasConflict: true,
                reason: 'Both events on same day, times unclear'
              }
            }
            
            // Parse times and check overlap
            // (Simplified - would need proper time parsing)
            return {
              hasConflict: event1.time === event2.time,
              reason: event1.time === event2.time ? 'Same time' : null
            }
          }
        }),
        
        // Tool 4: Get pending RSVPs
        getPendingRSVPs: tool({
          description: 'Get RSVPs that need responses',
          parameters: z.object({}),
          execute: async () => {
            const { data: rsvps } = await supabase
              .from('rsvp_tracking')
              .select(`
                *,
                event_name,
                deadline,
                event_date
              `)
              .eq('user_id', value: userId)
              .eq('status', value: 'pending')
              .order('deadline', { ascending: true })
            
            return rsvps || []
          }
        }),
        
        // Tool 5: Get approaching deadlines
        getDeadlines: tool({
          description: 'Get upcoming deadlines',
          parameters: z.object({
            daysAhead: z.number()
          }),
          execute: async ({ daysAhead }) => {
            const endDate = new Date()
            endDate.setDate(endDate.getDate() + daysAhead)
            
            const { data: deadlines } = await supabase
              .from('deadlines')
              .select('*')
              .eq('user_id', value: userId)
              .eq('status', value: 'pending')
              .lte('deadline', endDate.toISOString().split('T')[0])
              .order('deadline', { ascending: true })
            
            return deadlines || []
          }
        }),
        
        // Tool 6: Create reminder
        createReminder: tool({
          description: 'Create a reminder for the user',
          parameters: z.object({
            title: z.string(),
            reminderTime: z.string().describe('When to remind (ISO datetime)'),
            priority: z.enum(['low', 'medium', 'high', 'urgent'])
          }),
          execute: async ({ title, reminderTime, priority }) => {
            const { data } = await supabase
              .from('reminders')
              .insert({
                user_id: userId,
                title,
                reminder_time: reminderTime,
                priority,
                status: 'pending',
                created_by: 'ai'
              })
              .select()
              .single()
            
            return { success: true, reminderId: data?.id }
          }
        })
      }
    })
    
    // The result contains the final message and all tool calls
    return new Response(
      JSON.stringify({
        message: result.text,
        steps: result.steps?.map(step => ({
          type: step.type,
          toolCalls: step.toolCalls,
          toolResults: step.toolResults
        })),
        finishReason: result.finishReason
      }),
      { headers: { 'Content-Type': 'application/json' } }
    )
    
  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
```

### How the Agent Thinks (Example Execution)
```
User: "Check if there are any issues I need to handle."

Step 1: Agent calls getRecentMessages({ days: 3 })
  Returns: "Sarah: Soccer practice moved to Thursday 4pm
           Mike: Can you carpool Friday?
           Lisa: Birthday party Saturday 2pm - RSVP by Wednesday"

Step 2: Agent calls getCalendarEvents({ daysAhead: 7 })
  Returns: [
    { title: "Piano lesson", date: "2025-10-23", time: "16:00" },
    { title: "Doctor appointment", date: "2025-10-25", time: "14:00" }
  ]

Step 3: Agent calls checkConflicts({
  event1: { title: "Soccer practice", date: "2025-10-23", time: "16:00" },
  event2: { title: "Piano lesson", date: "2025-10-23", time: "16:00" }
})
  Returns: { hasConflict: true, reason: "Same time" }

Step 4: Agent calls getPendingRSVPs()
  Returns: [{ event_name: "Birthday party", deadline: "2025-10-22" }]

Step 5: Agent generates final response:
  "⚠️ I found a few things that need your attention:
  
  1. **Schedule Conflict**: Soccer practice was moved to Thursday at 4pm, 
     but you have a piano lesson at the same time. You'll need to 
     reschedule one of them.
  
  2. **RSVP Reminder**: You haven't responded to the birthday party 
     invitation yet. RSVP is due tomorrow (Wednesday).
  
  3. **Carpool Request**: Mike asked if you can carpool Friday. 
     Would you like me to check your Friday schedule?"
Swift Integration
swift
// Services/ProactiveAssistantService.swift
import Foundation

@MainActor
class ProactiveAssistantService: ObservableObject {
    @Published var currentAnalysis: ProactiveAnalysis?
    @Published var isAnalyzing = false
    @Published var lastChecked: Date?
    
    private let supabase = SupabaseClient.shared.client
    
    struct ProactiveAnalysis: Codable {
        let message: String
        let steps: [AnalysisStep]?
        let finishReason: String
        
        struct AnalysisStep: Codable {
            let type: String
            let toolCalls: [ToolCall]?
            let toolResults: [ToolResult]?
        }
        
        struct ToolCall: Codable {
            let name: String
            let arguments: String
        }
        
        struct ToolResult: Codable {
            let result: String
        }
    }
    
    func runProactiveCheck(conversationId: UUID, userId: UUID) async throws {
        isAnalyzing = true
        defer { isAnalyzing = false }
        
        let response = try await supabase.functions
            .invoke(
                "proactive-assistant",
                options: FunctionInvokeOptions(
                    body: [
                        "conversationId": conversationId.uuidString,
                        "userId": userId.uuidString
                    ]
                )
            )
        
        let decoder = JSONDecoder()
        let analysis = try decoder.decode(ProactiveAnalysis.self, from: response.data)
        
        self.currentAnalysis = analysis
        self.lastChecked = Date()
    }
}

// Views/AI/ProactiveAssistantView.swift
struct ProactiveAssistantView: View {
    let conversationId: UUID
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var assistant = ProactiveAssistantService()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundColor(.purple)
                    
                    VStack(alignment: .leading) {
                        Text("Proactive Assistant")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if let lastChecked = assistant.lastChecked {
                            Text("Last checked \(lastChecked, style: .relative) ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                
                // Analysis result
                if let analysis = assistant.currentAnalysis {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(analysis.message)
                            .padding()
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(12)
                        
                        // Show steps if in debug mode
                        #if DEBUG
                        if let steps = analysis.steps {
                            DisclosureGroup("Analysis Steps (\(steps.count))") {
                                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Step \(index + 1): \(step.type)")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        
                                        if let toolCalls = step.toolCalls {
                                            ForEach(Array(toolCalls.enumerated()), id: \.offset) { _, call in
                                                Text("• \(call.name)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .font(.caption)
                            .padding()
                        }
                        #endif
                    }
                    .padding()
                } else if assistant.isAnalyzing {
                    HStack {
                        ProgressView()
                        Text("Analyzing your schedule...")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    Text("Tap 'Check Now' to scan for scheduling issues and important items.")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
        .navigationTitle("Proactive Assistant")
        .toolbar {
            Button {
                Task {
                    guard let userId = authViewModel.currentUser?.id else { return }
                    try? await assistant.runProactiveCheck(
                        conversationId: conversationId,
                        userId: userId
                    )
                }
            } label: {
                Label("Check Now", systemImage: "arrow.clockwise")
            }
            .disabled(assistant.isAnalyzing)
        }
    }
}
Automatic Background Checks
For truly proactive behavior, run checks automatically:

swift
// Services/BackgroundAssistantService.swift
import Foundation
import BackgroundTasks

class BackgroundAssistantService {
    static let shared = BackgroundAssistantService()
    
    private let taskIdentifier = "com.messageai.proactive-check"
    
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            self.handleProactiveCheck(task: task as! BGAppRefreshTask)
        }
    }
    
    func scheduleNextCheck() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60) // 2 hours
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    private func handleProactiveCheck(task: BGAppRefreshTask) {
        scheduleNextCheck() // Schedule next check
        
        task.expirationHandler = {
            // Clean up if needed
        }
        
        Task {
            // Run proactive check for all active conversations
            // Send notification if issues found
            
            task.setTaskCompleted(success: true)
        }
    }
}
7. Database Schema
Complete SQL Schema
sql
-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_net"; -- For HTTP requests from triggers

-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP,
  status TEXT DEFAULT 'offline',
  push_token TEXT
);

-- Conversations table
CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT,
  avatar_url TEXT,
  is_group BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Conversation participants
CREATE TABLE conversation_participants (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMP DEFAULT NOW(),
  last_read_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (conversation_id, user_id)
);

-- Messages table
CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  message_type TEXT DEFAULT 'text',
  media_url TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP,
  local_id TEXT UNIQUE
);

-- Typing indicators
CREATE TABLE typing_indicators (
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  last_typed TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (conversation_id, user_id)
);

-- Read receipts
CREATE TABLE read_receipts (
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  read_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);

-- ============================================================================
-- AI FEATURE TABLES
-- ============================================================================

-- Calendar events extracted by AI
CREATE TABLE calendar_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  date DATE NOT NULL,
  time TIME,
  location TEXT,
  description TEXT,
  category TEXT NOT NULL,
  confidence FLOAT NOT NULL,
  confirmed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Decisions tracked from conversations
CREATE TABLE decisions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  decision_text TEXT NOT NULL,
  category TEXT NOT NULL,
  decided_by UUID REFERENCES users(id),
  deadline DATE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Priority messages flagged by AI
CREATE TABLE priority_messages (
  message_id UUID PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
  priority TEXT NOT NULL,
  reason TEXT NOT NULL,
  action_required BOOLEAN DEFAULT FALSE,
  dismissed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- RSVP tracking
CREATE TABLE rsvp_tracking (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  event_name TEXT NOT NULL,
  requested_by UUID REFERENCES users(id),
  deadline DATE,
  event_date DATE NOT NULL,
  status TEXT DEFAULT 'pending',
  response TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  responded_at TIMESTAMP,
  UNIQUE(message_id, user_id)
);

-- Deadlines extracted from messages
CREATE TABLE deadlines (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  task TEXT NOT NULL,
  deadline DATE NOT NULL,
  category TEXT NOT NULL,
  priority TEXT NOT NULL,
  details TEXT,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP
);

-- Reminders (AI-created and user-created)
CREATE TABLE reminders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  reminder_time TIMESTAMP NOT NULL,
  priority TEXT DEFAULT 'medium',
  status TEXT DEFAULT 'pending',
  created_by TEXT DEFAULT 'user',
  created_at TIMESTAMP DEFAULT NOW()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Core messaging indexes
CREATE INDEX idx_messages_conversation_created ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_local_id ON messages(local_id);
CREATE INDEX idx_conversation_participants_user ON conversation_participants(user_id);
CREATE INDEX idx_conversation_participants_conversation ON conversation_participants(conversation_id);
CREATE INDEX idx_conversations_updated ON conversations(updated_at DESC);
CREATE INDEX idx_users_push_token ON users(push_token);

-- AI feature indexes
CREATE INDEX idx_calendar_events_conversation ON calendar_events(conversation_id);
CREATE INDEX idx_calendar_events_date ON calendar_events(date);
CREATE INDEX idx_calendar_events_confirmed ON calendar_events(confirmed);
CREATE INDEX idx_decisions_conversation ON decisions(conversation_id);
CREATE INDEX idx_decisions_deadline ON decisions(deadline);
CREATE INDEX idx_priority_messages_priority ON priority_messages(priority);
CREATE INDEX idx_priority_messages_dismissed ON priority_messages(dismissed);
CREATE INDEX idx_rsvp_tracking_user_status ON rsvp_tracking(user_id, status);
CREATE INDEX idx_rsvp_tracking_deadline ON rsvp_tracking(deadline);
CREATE INDEX idx_deadlines_user_status ON deadlines(user_id, status, deadline);
CREATE INDEX idx_reminders_user_time ON reminders(user_id, reminder_time, status);
CREATE INDEX idx_read_receipts_message ON read_receipts(message_id);
CREATE INDEX idx_read_receipts_user ON read_receipts(user_id);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE typing_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE read_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE priority_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE rsvp_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE deadlines ENABLE ROW LEVEL SECURITY;
ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;

-- User policies
CREATE POLICY "Public profiles viewable by everyone" ON users
  FOR SELECT USING (true);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

-- Conversation policies
CREATE POLICY "Users can view own conversations" ON conversations
  FOR SELECT USING (
    id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create conversations" ON conversations
  FOR INSERT WITH CHECK (true);

-- Participant policies
CREATE POLICY "Users can view participants in own conversations" ON conversation_participants
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can add participants" ON conversation_participants
  FOR INSERT WITH CHECK (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

-- Message policies
CREATE POLICY "Users can view messages in their conversations" ON messages
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can send messages" ON messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid() AND
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

-- Typing indicator policies
CREATE POLICY "Users can view typing in their conversations" ON typing_indicators
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update own typing status" ON typing_indicators
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own typing status (update)" ON typing_indicators
  FOR UPDATE USING (user_id = auth.uid());

-- Read receipt policies
CREATE POLICY "Users can view read receipts in their conversations" ON read_receipts
  FOR SELECT USING (
    message_id IN (
      SELECT id FROM messages WHERE conversation_id IN (
        SELECT conversation_id FROM conversation_participants
        WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Users can insert own read receipts" ON read_receipts
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- AI feature policies
CREATE POLICY "Users can view calendar events in their conversations" ON calendar_events
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can view decisions in their conversations" ON decisions
  FOR SELECT USING (
    conversation_id IN (
      SELECT conversation_id FROM conversation_participants
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can view priority messages in their conversations" ON priority_messages
  FOR SELECT USING (
    message_id IN (
      SELECT id FROM messages WHERE conversation_id IN (
        SELECT conversation_id FROM conversation_participants
        WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Users can view own RSVPs" ON rsvp_tracking
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can view own deadlines" ON deadlines
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can view own reminders" ON reminders
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can update own reminders" ON reminders
  FOR UPDATE USING (user_id = auth.uid());

-- ============================================================================
-- TRIGGERS AND FUNCTIONS
-- ============================================================================

-- Update conversation timestamp on new message
CREATE OR REPLACE FUNCTION update_conversation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE conversations
  SET updated_at = NEW.created_at
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_conversation_on_message
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_conversation_timestamp();

-- Send push notification on new message (optional)
CREATE OR REPLACE FUNCTION notify_new_message()
RETURNS TRIGGER AS $$
DECLARE
  participant RECORD;
BEGIN
  FOR participant IN
    SELECT user_id
    FROM conversation_participants
    WHERE conversation_id = NEW.conversation_id
      AND user_id != NEW.sender_id
  LOOP
    PERFORM net.http_post(
      url := current_setting('app.edge_function_url') || '/send-notification',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'userId', participant.user_id,
        'title', 'New message',
        'body', LEFT(NEW.content, 100),
        'conversationId', NEW.conversation_id
      )
    );
  END LOOP;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Uncomment to enable push notifications
-- CREATE TRIGGER trigger_notify_new_message
--   AFTER INSERT ON messages
--   FOR EACH ROW
--   EXECUTE FUNCTION notify_new_message();
8. Implementation Timeline
Day-by-Day Plan (Full-Time with AI Assistance)
Total Development Time: 7 days (8-10 hours/day)

Day 1 (Monday) - Foundation
Goal: Authentication + Basic Messaging Working

Hours 0-2: Project Setup

 Create Supabase project
 Run database schema SQL
 Get API keys (Supabase, OpenAI)
 Create new Xcode project (iOS 17+)
 Add Supabase Swift SDK via SPM
 Set up folder structure
Hours 2-6: Authentication

 Create SupabaseClient singleton
 Build User model
 Implement AuthViewModel
 Create LoginView and SignUpView
 Test auth flow on simulator
 Test on physical device
Hours 6-10: Basic Chat

 Create Message and Conversation models
 Build ChatViewModel with send/receive
 Create ChatView UI
 Implement MessageRow component
 Test messaging between 2 devices
Evening Milestone: Two physical devices can send messages to each other.

Day 2 (Tuesday) - Real-Time & Offline
Goal: Messages sync in real-time + work offline

Hours 0-4: Realtime Subscriptions

 Implement Realtime message subscriptions
 Add typing indicators
 Test message delivery speed
 Handle connection errors
Hours 4-8: Local Persistence

 Set up SwiftData models
 Implement LocalStorageService
 Build MessageSyncService
 Add NetworkMonitor
Hours 8-10: Testing & Refinement

 Test offline message sending
 Test app restart persistence
 Test sync on reconnect
 Fix any sync bugs
Evening Milestone: Messages work offline and sync when reconnected.

Day 3 (Wednesday) - Group Chat & Notifications
Goal: Group chat + Push notifications

Hours 0-3: Group Chat

 Build ConversationService
 Implement group creation
 Add participant management
 Update UI for groups
**Hours 3-6: Rea








Supabase product requirements document - Claude