import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { S3Client, PutObjectCommand } from "npm:@aws-sdk/client-s3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    );

    // 1. Authenticate user via JWT Authorization header
    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Ensure only 'writer' or 'admin' roles can access it
    const { data: userProfile, error: profileError } = await supabaseClient
      .from("users")
      .select("role")
      .eq("id", user.id)
      .single();

    if (profileError || !userProfile || !["writer", "admin"].includes(userProfile.role)) {
      return new Response(
        JSON.stringify({ error: "Forbidden: Only writers and admins can request upload URLs" }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Parse payload to get fileExtension and fileSize
    const payload = await req.json().catch(() => ({}));
    const fileExtension = payload.fileExtension || ".pdf";
    const fileSize = payload.fileSize;

    // Cover image max 1MB size
    const imageExtensions = [".jpg", ".jpeg", ".png", ".webp", ".gif"];
    if (imageExtensions.includes(fileExtension.toLowerCase())) {
      if (fileSize && fileSize > 1 * 1024 * 1024) {
        return new Response(
          JSON.stringify({ error: "Cover image must not exceed 1MB" }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
    }

    let contentType = "application/octet-stream";
    if (fileExtension === ".epub") contentType = "application/epub+zip";
    else if (fileExtension === ".pdf") contentType = "application/pdf";
    else if (fileExtension === ".jpg" || fileExtension === ".jpeg") contentType = "image/jpeg";
    else if (fileExtension === ".png") contentType = "image/png";
    else if (fileExtension === ".webp") contentType = "image/webp";
    else if (fileExtension === ".gif") contentType = "image/gif";

    // 3. Generate unique file name
    const fileKey = `${crypto.randomUUID()}${fileExtension}`;

    // 4. Initialize S3Client for Cloudflare R2
    const s3Client = new S3Client({
      region: "auto",
      endpoint: Deno.env.get("R2_ENDPOINT"),
      credentials: {
        accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID")!,
        secretAccessKey: Deno.env.get("R2_SECRET_ACCESS_KEY")!,
      },
    });

    const command = new PutObjectCommand({
      Bucket: Deno.env.get("R2_BUCKET_NAME"),
      Key: fileKey,
      ContentType: contentType,
    });

    // 5. Generate 5-minute (300 seconds) presigned PUT URL
    const uploadUrl = await getSignedUrl(s3Client, command, { expiresIn: 300 });

    return new Response(JSON.stringify({ uploadUrl, fileKey }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
