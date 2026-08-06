"use client";
/* eslint-disable @next/next/no-html-link-for-pages */

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";
import { createSupabaseClient } from "@/lib/supabase";

type Employee = { id: string; full_name: string; employee_number: string };
type Row = {
  id: string;
  employee_id: string;
  event_type: string;
  occurred_at: string;
  location_unavailable: boolean;
  kiosk_devices: { name: string } | null;
  employees: Employee | null;
};

export default function ReportsPage() {
  const router = useRouter(),
    db = useRef<SupabaseClient | null>(null);
  const [rows, setRows] = useState<Row[]>([]),
    [employees, setEmployees] = useState<Employee[]>([]),
    [search, setSearch] = useState(""),
    [employee, setEmployee] = useState("all"),
    [from, setFrom] = useState(() =>
      new Date(new Date().getFullYear(), new Date().getMonth(), 1)
        .toISOString()
        .slice(0, 10),
    ),
    [to, setTo] = useState(() => new Date().toISOString().slice(0, 10));
  useEffect(() => {
    const client = createSupabaseClient();
    db.current = client;
    client.auth.getUser().then(async ({ data }) => {
      if (!data.user) return router.replace("/login");
      const [{ data: e }, { data: r }] = await Promise.all([
        client
          .from("employees")
          .select("id,full_name,employee_number")
          .order("full_name"),
        client
          .from("kiosk_attendance_events")
          .select(
            "id,employee_id,event_type,occurred_at,location_unavailable,kiosk_devices(name),employees(id,full_name,employee_number)",
          )
          .order("occurred_at", { ascending: false })
          .limit(2000),
      ]);
      setEmployees((e || []) as Employee[]);
      setRows((r || []) as unknown as Row[]);
    });
  }, [router]);
  const filtered = useMemo(
    () =>
      rows.filter((r) => {
        const day = r.occurred_at.slice(0, 10),
          q = search.toLowerCase();
        return (
          day >= from &&
          day <= to &&
          (employee === "all" || r.employee_id === employee) &&
          (!q ||
            r.employees?.full_name.toLowerCase().includes(q) ||
            r.employees?.employee_number.toLowerCase().includes(q))
        );
      }),
    [rows, search, employee, from, to],
  );
  const people = new Set(filtered.map((r) => r.employee_id)).size,
    clockIns = filtered.filter((r) => r.event_type === "clock_in").length,
    flags = filtered.filter((r) => r.location_unavailable).length;
  function exportCsv() {
    const lines = [
      [
        "Employee",
        "Employee ID",
        "Action",
        "Date and time",
        "Kiosk",
        "Location",
      ],
      ...filtered.map((r) => [
        r.employees?.full_name || "",
        r.employees?.employee_number || "",
        r.event_type,
        new Date(r.occurred_at).toLocaleString("en-PH"),
        r.kiosk_devices?.name || "",
        r.location_unavailable ? "Flagged" : "Captured",
      ]),
    ];
    const csv = lines
      .map((line) =>
        line.map((v) => `"${String(v).replaceAll('"', '""')}"`).join(","),
      )
      .join("\n");
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `attendance-${from}-${to}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }
  return (
    <main className="admin-page">
      <header className="admin-top">
        <div className="brand login-brand">
          <b>P</b> PulseHR Reports
        </div>
        <div>
          <a href="/attendance">Attendance admin</a>
          <a href="/">Dashboard</a>
        </div>
      </header>
      <div className="admin-content">
        <div className="admin-title">
          <small>TRACEABILITY</small>
          <h1>Attendance reports</h1>
          <p>
            Search the complete kiosk history or select one employee for an
            individual trace.
          </p>
        </div>
        <section className="card report-filters">
          <label>
            Search
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Name or Employee ID"
            />
          </label>
          <label>
            Employee
            <select
              value={employee}
              onChange={(e) => setEmployee(e.target.value)}
            >
              <option value="all">All employees</option>
              {employees.map((e) => (
                <option key={e.id} value={e.id}>
                  {e.full_name}
                </option>
              ))}
            </select>
          </label>
          <label>
            From
            <input
              type="date"
              value={from}
              onChange={(e) => setFrom(e.target.value)}
            />
          </label>
          <label>
            To
            <input
              type="date"
              value={to}
              onChange={(e) => setTo(e.target.value)}
            />
          </label>
          <button className="primary" onClick={exportCsv}>
            Export CSV
          </button>
        </section>
        <section className="report-stats">
          <article className="card">
            <small>EMPLOYEES</small>
            <b>{people}</b>
          </article>
          <article className="card">
            <small>CLOCK-INS</small>
            <b>{clockIns}</b>
          </article>
          <article className="card">
            <small>EVENTS</small>
            <b>{filtered.length}</b>
          </article>
          <article className="card">
            <small>LOCATION FLAGS</small>
            <b>{flags}</b>
          </article>
        </section>
        <section className="card admin-table">
          <div className="attendance-report-tr head">
            <span>Employee</span>
            <span>Action</span>
            <span>Date & time</span>
            <span>Kiosk</span>
            <span>Location</span>
          </div>
          {filtered.map((r) => (
            <div className="attendance-report-tr" key={r.id}>
              <span>
                {r.employees?.full_name}
                <small>{r.employees?.employee_number}</small>
              </span>
              <span>
                {r.event_type === "clock_in" ? "Clock in" : "Clock out"}
              </span>
              <span>{new Date(r.occurred_at).toLocaleString("en-PH")}</span>
              <span>{r.kiosk_devices?.name || "—"}</span>
              <span>{r.location_unavailable ? "Flagged" : "Captured"}</span>
            </div>
          ))}
        </section>
      </div>
    </main>
  );
}
