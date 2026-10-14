-- جدول طلبات التسجيل في نظام الجودة
create table if not exists public.quality_signup_requests (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null,
  phone text,
  req_role text,
  unit text,
  note text,
  status text not null default 'pending',
  handled_by text,
  handled_at timestamptz,
  created_at timestamptz default now()
);
alter table public.quality_signup_requests enable row level security;
grant insert on public.quality_signup_requests to anon, authenticated;
grant select, update on public.quality_signup_requests to authenticated;

drop policy if exists sr_insert on public.quality_signup_requests;
create policy sr_insert on public.quality_signup_requests for insert to anon, authenticated
  with check (status = 'pending' and lower(email) like '%@nwc.com.sa');

drop policy if exists sr_admin_read on public.quality_signup_requests;
create policy sr_admin_read on public.quality_signup_requests for select to authenticated
  using (exists (select 1 from public.quality_users u where u.id = auth.uid() and u.role = 'admin' and u.active));

drop policy if exists sr_admin_update on public.quality_signup_requests;
create policy sr_admin_update on public.quality_signup_requests for update to authenticated
  using (exists (select 1 from public.quality_users u where u.id = auth.uid() and u.role = 'admin' and u.active));

-- حذف الجداول التجريبية التي أُنشئت سابقاً ولا تستخدمها المنصة
drop table if exists public.qa_evaluations, public.qa_audits, public.qa_violations, public.qa_profiles cascade;
drop function if exists public.qa_role(), public.qa_sector(), public.qa_sync_status(), public.qa_guard_assign(), public.qa_lock_note() cascade;
