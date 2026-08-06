import { NextResponse } from "next/server";
import { getSupabaseConfiguration } from "@/lib/supabase";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const { url, publishableKey } = getSupabaseConfiguration();
    const response = await fetch(`${url}/auth/v1/health`, {
      headers: { apikey: publishableKey },
      cache: "no-store",
    });

    if (!response.ok) {
      return NextResponse.json({ connected: false }, { status: 503 });
    }

    return NextResponse.json({ connected: true });
  } catch {
    return NextResponse.json({ connected: false }, { status: 503 });
  }
}
