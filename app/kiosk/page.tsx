"use client";
/* eslint-disable react-hooks/set-state-in-effect, @next/next/no-img-element */

import { FormEvent, useEffect, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createSupabaseClient } from "@/lib/supabase";

type Result = {
  employee_name: string;
  event_type: "clock_in" | "clock_out";
  occurred_at: string;
  location_flagged: boolean;
};
type Activity = Result;

export default function KioskPage() {
  const supabase = useRef<SupabaseClient | null>(null);
  const video = useRef<HTMLVideoElement | null>(null);
  const stream = useRef<MediaStream | null>(null);
  const [token, setToken] = useState("");
  const [selfie, setSelfie] = useState("");
  const [message, setMessage] = useState("");
  const [result, setResult] = useState<Result | null>(null);
  const [busy, setBusy] = useState(false);
  const [activity, setActivity] = useState<Activity[]>([]);
  const [activitySearch, setActivitySearch] = useState("");

  useEffect(() => {
    supabase.current = createSupabaseClient();
    setToken(localStorage.getItem("pulsehr_kiosk_token") || "");
    return () => stream.current?.getTracks().forEach((track) => track.stop());
  }, []);

  useEffect(() => {
    if (!token || !supabase.current) return;
    let active = true;
    const refresh = async () => {
      const { data } = await supabase.current!.rpc("kiosk_today_activity", {
        p_kiosk_token: token,
      });
      if (active && data) setActivity(data as Activity[]);
    };
    void refresh();
    const timer = setInterval(refresh, 3000);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [token]);

  async function startCamera() {
    setMessage("");
    try {
      stream.current?.getTracks().forEach((track) => track.stop());
      stream.current = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: 640, height: 480 },
        audio: false,
      });
      if (video.current) {
        video.current.srcObject = stream.current;
        await video.current.play();
      }
    } catch {
      setMessage("Camera access is required for attendance.");
    }
  }

  function capture() {
    if (!video.current?.videoWidth)
      return setMessage("Start the camera first.");
    const canvas = document.createElement("canvas");
    canvas.width = 360;
    canvas.height = 270;
    canvas.getContext("2d")?.drawImage(video.current, 0, 0, 360, 270);
    setSelfie(canvas.toDataURL("image/jpeg", 0.72));
    stream.current?.getTracks().forEach((track) => track.stop());
  }

  async function clock(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selfie) return setMessage("Capture a selfie before continuing.");
    const form = new FormData(event.currentTarget);
    setBusy(true);
    setMessage("");
    setResult(null);
    let latitude: number | null = null,
      longitude: number | null = null;
    try {
      const location = await new Promise<GeolocationPosition>(
        (resolve, reject) =>
          navigator.geolocation.getCurrentPosition(resolve, reject, {
            enableHighAccuracy: true,
            timeout: 8000,
          }),
      );
      latitude = location.coords.latitude;
      longitude = location.coords.longitude;
    } catch {
      /* allow and flag */
    }
    const { data, error } = await supabase.current!.rpc("kiosk_clock", {
      p_kiosk_token: token,
      p_employee_number: form.get("employee_number"),
      p_pin: form.get("pin"),
      p_selfie_data: selfie,
      p_latitude: latitude,
      p_longitude: longitude,
    });
    setBusy(false);
    if (error) return setMessage(error.message);
    setResult(data as Result);
    setSelfie("");
    event.currentTarget.reset();
  }

  if (!token)
    return (
      <main className="kiosk-page">
        <section className="kiosk-card setup">
          <div className="brand login-brand">
            <b>P</b> PulseHR Kiosk
          </div>
          <h1>Activate this device</h1>
          <p>
            Ask an administrator to create a one-time kiosk token from the
            Attendance page.
          </p>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const value = String(
                new FormData(e.currentTarget).get("token"),
              ).trim();
              localStorage.setItem("pulsehr_kiosk_token", value);
              setToken(value);
            }}
          >
            <label>
              Kiosk token
              <input name="token" required />
            </label>
            <button className="primary">Activate kiosk</button>
          </form>
        </section>
      </main>
    );

  return (
    <main className="kiosk-page">
      <section className="kiosk-card">
        <header className="kiosk-head">
          <div className="brand login-brand">
            <b>P</b> PulseHR Kiosk
          </div>
          <button
            onClick={() => {
              localStorage.removeItem("pulsehr_kiosk_token");
              setToken("");
            }}
          >
            Reset device
          </button>
        </header>
        <div className="kiosk-time">
          {new Intl.DateTimeFormat("en-PH", {
            dateStyle: "full",
            timeStyle: "short",
            timeZone: "Asia/Manila",
          }).format(new Date())}
        </div>
        {result ? (
          <div className="kiosk-success">
            <i>✓</i>
            <h1>
              {result.event_type === "clock_in"
                ? "Clock-in recorded"
                : "Clock-out recorded"}
            </h1>
            <h2>{result.employee_name}</h2>
            <p>
              {new Date(result.occurred_at).toLocaleTimeString("en-PH", {
                hour: "numeric",
                minute: "2-digit",
              })}
              {result.location_flagged
                ? " · Location flagged for review"
                : " · Location captured"}
            </p>
            <button className="primary" onClick={() => setResult(null)}>
              Next employee
            </button>
          </div>
        ) : (
          <form className="kiosk-form" onSubmit={clock}>
            <div className="camera">
              <video ref={video} muted playsInline />
              {selfie && <img src={selfie} alt="Captured attendance selfie" />}
            </div>
            <div className="camera-actions">
              <button type="button" onClick={startCamera}>
                Start camera
              </button>
              <button type="button" onClick={capture}>
                Capture selfie
              </button>
            </div>
            <label>
              Employee ID
              <input name="employee_number" autoComplete="off" required />
            </label>
            <label>
              Private PIN
              <input
                name="pin"
                type="password"
                inputMode="numeric"
                pattern="[0-9]{4,8}"
                required
              />
            </label>
            {message && <div className="login-message">{message}</div>}
            <button className="primary clock-submit" disabled={busy}>
              {busy ? "Recording…" : "Record attendance"}
            </button>
          </form>
        )}
        <section className="kiosk-activity">
          <div className="kiosk-activity-head">
            <div>
              <h2>Today&apos;s attendance</h2>
              <p>Latest 10 shown · scroll for earlier events</p>
            </div>
            <input
              value={activitySearch}
              onChange={(event) => setActivitySearch(event.target.value)}
              placeholder="Search name"
              aria-label="Search today's attendance"
            />
          </div>
          <div className="kiosk-activity-list">
            {activity
              .filter((event) =>
                event.employee_name
                  .toLowerCase()
                  .includes(activitySearch.toLowerCase()),
              )
              .map((event, index) => (
                <div
                  className="kiosk-activity-row"
                  key={`${event.occurred_at}-${index}`}
                >
                  <strong>{event.employee_name}</strong>
                  <span>
                    {event.event_type === "clock_in" ? "Clock in" : "Clock out"}
                  </span>
                  <time>
                    {new Date(event.occurred_at).toLocaleTimeString("en-PH", {
                      hour: "numeric",
                      minute: "2-digit",
                    })}
                  </time>
                  <em className={event.location_flagged ? "flagged" : ""}>
                    {event.location_flagged ? "Flagged" : "Captured"}
                  </em>
                </div>
              ))}
            {!activity.length && (
              <p className="kiosk-empty">No attendance recorded today.</p>
            )}
          </div>
        </section>
      </section>
    </main>
  );
}
