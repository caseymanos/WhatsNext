import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { create } from "https://deno.land/x/djwt@v3.0.1/mod.ts";

// APNs configuration
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") || "";
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") || "";
const APNS_KEY = Deno.env.get("APNS_KEY") || "";
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") || "com.gauntletai.whatsnext";
const APNS_ENVIRONMENT = Deno.env.get("APNS_ENVIRONMENT") || "development"; // development or production

// APNs endpoint
const APNS_URL = APNS_ENVIRONMENT === "production"
  ? "https://api.push.apple.com"
  : "https://api.sandbox.push.apple.com";

interface NotificationPayload {
  userId: string;
  title: string;
  body: string;
  conversationId?: string;
  messageId?: string;
  senderId?: string;
  senderName?: string;
}

// Generate APNs JWT token
async function generateAPNsToken(): Promise<string> {
  if (!APNS_KEY || !APNS_KEY_ID || !APNS_TEAM_ID) {
    throw new Error("APNs credentials not configured");
  }

  // Parse the private key (PEM format)
  const keyData = APNS_KEY.replace(/\\n/g, "\n");
  
  // Import the key for ES256 signing
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    new TextEncoder().encode(keyData),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );

  const jwt = await create(
    { alg: "ES256", kid: APNS_KEY_ID },
    {
      iss: APNS_TEAM_ID,
      iat: Math.floor(Date.now() / 1000),
    },
    privateKey
  );

  return jwt;
}

// Send notification to APNs
async function sendToAPNs(deviceToken: string, payload: NotificationPayload): Promise<boolean> {
  try {
    const apnsToken = await generateAPNsToken();
    
    const apnsPayload = {
      aps: {
        alert: {
          title: payload.title,
          body: payload.body,
        },
        sound: "default",
        badge: 1,
        "mutable-content": 1,
        category: "MESSAGE",
      },
      conversation_id: payload.conversationId,
      message_id: payload.messageId,
      sender_id: payload.senderId,
      sender_name: payload.senderName,
    };

    const response = await fetch(`${APNS_URL}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        "authorization": `bearer ${apnsToken}`,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-topic": APNS_BUNDLE_ID,
        "content-type": "application/json",
      },
      body: JSON.stringify(apnsPayload),
    });

    if (!response.ok) {
      const errorBody = await response.text();
      console.error(`APNs error (${response.status}): ${errorBody}`);
      return false;
    }

    return true;
  } catch (error) {
    console.error("Error sending to APNs:", error);
    return false;
  }
}

serve(async (req) => {
  try {
    // Parse request body
    const payload: NotificationPayload = await req.json();
    
    // Validate required fields
    if (!payload.userId || !payload.title || !payload.body) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: userId, title, body" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase client with service role key
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    
    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({ error: "Supabase configuration missing" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Fetch user's push token
    const { data: user, error: userError } = await supabase
      .from("users")
      .select("push_token")
      .eq("id", payload.userId)
      .single();

    if (userError || !user) {
      console.error("Error fetching user:", userError);
      return new Response(
        JSON.stringify({ error: "User not found" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // Check if user has a push token
    if (!user.push_token) {
      console.log(`User ${payload.userId} has no push token registered`);
      return new Response(
        JSON.stringify({ success: false, reason: "No push token registered" }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // Check if APNs is configured
    if (!APNS_KEY || !APNS_KEY_ID || !APNS_TEAM_ID) {
      console.warn("APNs not configured, skipping push notification");
      return new Response(
        JSON.stringify({ success: false, reason: "APNs not configured" }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // Send notification to APNs
    const sent = await sendToAPNs(user.push_token, payload);

    if (sent) {
      return new Response(
        JSON.stringify({
          success: true,
          userId: payload.userId,
          conversationId: payload.conversationId,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    } else {
      return new Response(
        JSON.stringify({
          success: false,
          reason: "Failed to send to APNs",
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  } catch (error) {
    console.error("Unexpected error:", error);
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

