# PulseHR HRIS

PulseHR is a responsive Philippine HRIS MVP covering online attendance, geofence verification feedback, leave requests, employee attendance history, leave balances, and payroll previews.

## Local development

```bash
npm install
npm run dev
```

Open `http://localhost:3000`.

## Production build

```bash
npm run build
npm start
```

## Deploying to Vercel

Import this GitHub repository into Vercel. Vercel should detect Next.js automatically; no custom build or output settings are required for this UI checkpoint.

Configure these project environment variables for Production and Preview:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
```

The header database indicator verifies the deployed application can reach Supabase Auth. Apply the SQL migration in `supabase/migrations` before enabling persistent HRIS workflows.

## Current scope

This repository contains the first interactive product checkpoint and uses representative demo data. Production persistence, authentication, role-based access, approval workflows, payroll computation, and official effective-dated contribution tables are the next implementation phase.
