"use client";

import { FormEvent, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createSupabaseClient } from "@/lib/supabase";

export default function LoginPage() {
  const router = useRouter();
  const supabaseRef = useRef<SupabaseClient | null>(null);
  const [signup, setSignup] = useState(false);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const supabase = createSupabaseClient();
    supabaseRef.current = supabase;
    supabase.auth.getUser().then(({ data }) => data.user && router.replace("/"));
  }, [router]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const supabase = supabaseRef.current;
    if (!supabase) return;
    setBusy(true);
    setMessage("");
    const fields = new FormData(event.currentTarget);
    const email = String(fields.get("email"));
    const password = String(fields.get("password"));

    if (signup) {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: { data: { full_name: fields.get("full_name"), company_name: fields.get("company_name") } },
      });
      setBusy(false);
      if (error) return setMessage(error.message);
      if (!data.session) return setMessage("Check your email to confirm your account, then sign in.");
      router.replace("/");
      return;
    }

    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) return setMessage(error.message);
    router.replace("/");
  }

  return <main className="login-page"><section className="login-card"><div className="brand login-brand"><b>P</b> PulseHR</div><small>PHILIPPINE HRIS</small><h1>{signup ? "Create your company" : "Welcome back"}</h1><p>{signup ? "Create the first administrator account for your HRIS." : "Sign in to manage attendance, leave, and payroll."}</p><form onSubmit={submit}>{signup && <><label>Full name<input name="full_name" required /></label><label>Company name<input name="company_name" required /></label></>}<label>Email<input name="email" type="email" required /></label><label>Password<input name="password" type="password" minLength={8} required /></label>{message && <div className="login-message">{message}</div>}<button className="primary" disabled={busy}>{busy ? "Please wait…" : signup ? "Create account" : "Sign in"}</button></form><button className="login-switch" onClick={()=>{setSignup(!signup);setMessage("")}}>{signup ? "Already registered? Sign in" : "First company administrator? Create account"}</button></section></main>;
}
