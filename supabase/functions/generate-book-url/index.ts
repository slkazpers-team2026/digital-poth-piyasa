import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { S3Client, GetObjectCommand } from "npm:@aws-sdk/client-s3";
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
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: {
          headers: { Authorization: req.headers.get("Authorization")! },
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

    const payload = await req.json();
    const book_id = payload.book_id ?? payload.bookId;
    const isPreview = payload.isPreview;

    if (!book_id) {
      return new Response(
        JSON.stringify({ error: "Missing book_id in request body" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let targetFileKey: string;

    const { data: book, error: bookError } = await supabaseClient
      .from("books")
      .select("r2_full_file_key")
      .eq("id", book_id)
      .single();

    if (bookError || !book || !book.r2_full_file_key) {
      return new Response(JSON.stringify({ error: "Book not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    targetFileKey = book.r2_full_file_key;

    // 3. Generate Presigned URL
    const s3Client = new S3Client({
      region: "auto",
      endpoint: Deno.env.get("R2_ENDPOINT"),
      credentials: {
        accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID")!,
        secretAccessKey: Deno.env.get("R2_SECRET_ACCESS_KEY")!,
      },
    });

    const command = new GetObjectCommand({
      Bucket: Deno.env.get("R2_BUCKET_NAME"),
      Key: targetFileKey,
    });

    // Generate a 5-minute (300 seconds) presigned GET URL without restricting browser headers
    const signedUrl = await getSignedUrl(s3Client, command, {
      expiresIn: 300,
      signableHeaders: new Set(),
    });

    return new Response(JSON.stringify({ signedUrl }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
