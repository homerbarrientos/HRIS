"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createSupabaseClient } from "@/lib/supabase";

const rows = [
  ["Mon · Aug 3", "7:56 AM", "5:08 PM", "8h 12m", "On time"],
  ["Tue · Aug 4", "8:07 AM", "5:14 PM", "8h 07m", "Grace"],
  ["Wed · Aug 5", "7:51 AM", "5:03 PM", "8h 12m", "On time"],
  ["Thu · Aug 6", "8:02 AM", "—", "3h 42m", "Active"],
];

const nav = ["Overview", "Time & attendance", "Leave", "Payroll", "People", "Reports"];

export default function Home() {
  const router = useRouter();
  const supabaseRef = useRef<SupabaseClient | null>(null);
  const [tab, setTab] = useState("Overview");
  const [clockedIn, setClockedIn] = useState(false);
  const [profile, setProfile] = useState<{ id: string; organization_id: string; full_name: string; employee_number: string } | null>(null);
  const [toast, setToast] = useState("");
  const [leave, setLeave] = useState(false);
  const [sent, setSent] = useState(false);
  const [databaseStatus, setDatabaseStatus] = useState<"checking" | "connected" | "error">("checking");

  useEffect(() => {
    fetch("/api/health/supabase", { cache: "no-store" })
      .then((response) => {
        if (!response.ok) throw new Error("Supabase health check failed");
        setDatabaseStatus("connected");
      })
      .catch(() => setDatabaseStatus("error"));

    const supabase = createSupabaseClient();
    supabaseRef.current = supabase;
    supabase.auth.getUser().then(async ({ data, error }) => {
      if (error || !data.user) {
        router.replace("/login");
        return;
      }

      const [{ data: employee }, { data: latestEvent }] = await Promise.all([
        supabase.from("profiles").select("id, organization_id, full_name, employee_number").eq("id", data.user.id).single(),
        supabase.from("attendance_events").select("event_type").eq("employee_id", data.user.id).order("occurred_at", { ascending: false }).limit(1).maybeSingle(),
      ]);
      if (employee) setProfile(employee);
      setClockedIn(latestEvent?.event_type === "clock_in" || latestEvent?.event_type === "break_end");
    });
  }, [router]);

  const toggleClock = async () => {
    const supabase = supabaseRef.current;
    if (!supabase || !profile) {
      setToast("Your employee profile is still loading.");
      return;
    }
    const next = !clockedIn;
    let latitude: number | null = null;
    let longitude: number | null = null;
    try {
      const position = await new Promise<GeolocationPosition>((resolve, reject) => navigator.geolocation.getCurrentPosition(resolve, reject, { enableHighAccuracy: true, timeout: 10000 }));
      latitude = position.coords.latitude;
      longitude = position.coords.longitude;
    } catch {
      // Attendance remains allowed and is flagged for HR review when location is unavailable.
    }
    const { error } = await supabase.from("attendance_events").insert({
      organization_id: profile.organization_id,
      employee_id: profile.id,
      event_type: next ? "clock_in" : "clock_out",
      latitude,
      longitude,
      outside_geofence: latitude === null,
      notes: latitude === null ? "Location unavailable; review required" : null,
    });
    if (error) {
      setToast(`Attendance was not saved: ${error.message}`);
      return;
    }
    setClockedIn(next);
    setToast(`${next ? "Clock-in" : "Clock-out"} saved${latitude === null ? " and flagged for location review" : " with location"}.`);
    setTimeout(() => setToast(""), 4000);
  };

  return <div className="shell">
    <aside>
      <div className="brand"><b>P</b> PulseHR</div>
      <div className="company"><i>NB</i><span><strong>Northstar Build Co.</strong><small>Philippines</small></span><b>⌄</b></div>
      <nav>{nav.map((item, i) => <button key={item} onClick={() => item === "Time & attendance" ? router.push("/attendance") : setTab(item)} className={tab === item ? "active" : ""}><span>{["⌂", "◷", "◇", "₱", "♙", "▥"][i]}</span>{item}{item === "Leave" && <em>2</em>}</button>)}</nav>
      <div className="aside-foot"><button>⚙ &nbsp; Settings</button><div className="person" onClick={async()=>{await supabaseRef.current?.auth.signOut();router.replace("/login")}}><i>{profile?.full_name.split(" ").map(x=>x[0]).join("").slice(0,2).toUpperCase() || "HR"}</i><span><strong>{profile?.full_name || "Loading profile"}</strong><small>Employee · {profile?.employee_number || "—"} · Sign out</small></span></div></div>
    </aside>
    <main>
      <header><button className="search">⌕ &nbsp; Search people, reports... <kbd>⌘ K</kbd></button><div><span className={`database-status ${databaseStatus}`}><i />{databaseStatus === "checking" ? "Connecting" : databaseStatus === "connected" ? "Database connected" : "Database unavailable"}</span><button>♢</button><button>?</button></div></header>
      <div className="content">
        {tab !== "Overview" ? <section className="empty card"><small>MODULE</small><h1>{tab}</h1><p>This module is part of the MVP. The first working slice focuses on attendance, leave, and payroll visibility.</p><button className="primary" onClick={() => setTab("Overview")}>Back to overview</button></section> : <>
          <section className="welcome"><div><small>THURSDAY, AUGUST 6</small><h1>Good morning, {profile?.full_name.split(" ")[0] || "there"}.</h1><p>Here’s your workday at a glance.</p></div><button className="outline" onClick={() => setLeave(true)}>＋ Request leave</button></section>
          <section className="hero">
            <article className="clock">
              <div className="clock-label"><i className={clockedIn ? "dot" : "dot off"}/>{clockedIn ? "CLOCKED IN" : "NOT CLOCKED IN"}<span>Asia/Manila</span></div>
              <div className="shift"><div><small>TODAY’S SHIFT</small><h2>8:00 AM — 5:00 PM</h2><p>● &nbsp;Makati HQ &nbsp;·&nbsp; Standard schedule</p></div><div className="timer"><strong>{clockedIn ? "3:42:18" : "—"}</strong><small>{clockedIn ? "Elapsed today" : "Ready for your shift"}</small></div></div>
              <div className="clock-action"><button onClick={toggleClock}>{clockedIn ? "□  Clock out" : "▶  Clock in"}</button><div><b>⌖</b><span><strong>Location verified</strong><small>Within Makati HQ geofence</small></span></div></div>
              <footer><span>10 min grace</span><span>·</span><span>1 hr unpaid break</span><span>·</span><span>Selfie verification on</span></footer>
            </article>
            <article className="week card"><div className="title"><div><small>THIS WEEK</small><h3>32h 13m</h3></div><span>of 40h</span></div><div className="bars">{[82,80,82,38,7].map((n,i)=><div key={i}><i style={{height:n}} className={i===3?"today":""}/><small>{["M","T","W","T","F"][i]}</small></div>)}</div><footer><span><b>＋12m</b> overtime</span><span><b>0</b> exceptions</span></footer></article>
          </section>
          <section className="stats">
            {[ ["✓","Attendance rate","98.4%","↑ 1.2% from last month"], ["◇","Leave balance","16 days","Across 3 leave types"], ["₱","Next payday","Aug 15","8 days remaining"], ["◷","Pending requests","2","1 leave · 1 overtime"] ].map((x,i)=><article className="card" key={x[1]}><i className={`stat-icon c${i}`}>{x[0]}</i><div><small>{x[1]}</small><strong>{x[2]}</strong><p>{x[3]}</p></div></article>)}
          </section>
          <section className="detail">
            <article className="card attendance"><div className="section-head"><div><h3>Recent attendance</h3><p>Your latest clock records</p></div><button onClick={()=>setTab("Time & attendance")}>View all →</button></div><div className="table"><div className="tr th"><span>DATE</span><span>CLOCK IN</span><span>CLOCK OUT</span><span>HOURS</span><span>STATUS</span></div>{rows.map(r=><div className="tr" key={r[0]}>{r.map((v,i)=><span key={i}>{i===4?<b className={`pill ${v.toLowerCase().replace(" ","")}`}>{v}</b>:v}</span>)}</div>)}</div></article>
            <article className="card balances"><div className="section-head"><div><h3>Leave balances</h3><p>As of August 6, 2026</p></div><button onClick={()=>setTab("Leave")}>Manage →</button></div>{[["Service incentive",3,5],["Company vacation",6,10],["Sick leave",7,8]].map((x,i)=><div className="balance" key={String(x[0])}><div><span>{x[0]}</span><b>{x[1]} <small>days left</small></b></div><div className="progress"><i className={`c${i}`} style={{width:`${Number(x[1])/Number(x[2])*100}%`}}/></div><small>{Number(x[2])-Number(x[1])} used of {x[2]}</small></div>)}</article>
          </section>
          <section className="pay card"><i>₱</i><div><small>UPCOMING PAYROLL</small><h3>August 1–15, 2026</h3><p>Semi-monthly · Payday August 15</p></div><div className="money"><span><small>EST. GROSS</small><b>₱32,500.00</b></span><span><small>EST. DEDUCTIONS</small><b>₱4,218.50</b></span><span><small>EST. NET PAY</small><b>₱28,281.50</b></span></div><button onClick={()=>setTab("Payroll")}>View breakdown →</button></section>
        </>}
      </div>
    </main>
    {toast && <div className="toast">✓ &nbsp; {toast}</div>}
    {leave && <div className="backdrop" onMouseDown={()=>setLeave(false)}><form className="modal" onMouseDown={e=>e.stopPropagation()} onSubmit={e=>{e.preventDefault();setSent(true);setTimeout(()=>{setLeave(false);setSent(false)},1300)}}><button type="button" className="close" onClick={()=>setLeave(false)}>×</button><small>NEW REQUEST</small><h2>Request leave</h2>{sent?<div className="success"><i>✓</i><h3>Request submitted</h3><p>Your manager has been notified.</p></div>:<><label>Leave type<select required defaultValue=""><option value="" disabled>Select leave type</option><option>Service incentive leave</option><option>Company vacation</option><option>Sick leave</option></select></label><div className="dates"><label>From<input required type="date"/></label><label>To<input required type="date"/></label></div><label>Reason<textarea placeholder="Add a short note for your manager"/></label><div className="modal-actions"><button type="button" className="outline" onClick={()=>setLeave(false)}>Cancel</button><button className="primary">Submit request</button></div></>}</form></div>}
  </div>
}
