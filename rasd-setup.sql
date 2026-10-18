-- =====================================================================
-- جودة الرصد — عينة شهرية يقيّمها المركز الرئيسي
-- يُشغَّل مرة واحدة في Supabase ← SQL Editor
-- =====================================================================

create table if not exists public.quality_rasd (
  month      text not null,               -- الشهر بصيغة YYYY-MM
  visit_no   text not null,               -- رقم الزيارة
  visit      text,
  sec        text,                        -- القطاع
  gov        text,                        -- المحافظة
  region     text,
  officer    text,                        -- مأمور الضبط
  mgr        text,                        -- مدير الرقابة
  item       text,                        -- بند المخالفة
  vdate      text,                        -- تاريخ الزيارة
  ans        jsonb not null default '{}'::jsonb,  -- إجابات المعايير الستة (1 تجاوز / 0 لم يتجاوز)
  note       text,
  score      numeric,                     -- درجة جودة الرصد %
  eval_by    uuid,
  eval_name  text,
  eval_at    timestamptz,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (month, visit_no)
);

-- موظف المركز الرئيسي؟ (مدير النظام، المدير التنفيذي، أو قطاعه المركز الرئيسي)
create or replace function public.q_is_hq() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.quality_users
    where id = auth.uid() and active
      and (role in ('admin','exec') or coalesce(sector,'') like '%المركز الرئيسي%')
  )
$$;

alter table public.quality_rasd enable row level security;

drop policy if exists qr_select on public.quality_rasd;
drop policy if exists qr_insert on public.quality_rasd;
drop policy if exists qr_update on public.quality_rasd;
drop policy if exists qr_delete on public.quality_rasd;

-- الكل يقرأ (كل قطاع يرى نتائجه فقط داخل المنصة)
create policy qr_select on public.quality_rasd for select using (public.q_role() is not null);
-- السحب والتقييم للمركز الرئيسي فقط
create policy qr_insert on public.quality_rasd for insert with check (public.q_is_hq());
create policy qr_update on public.quality_rasd for update using (public.q_is_hq());
create policy qr_delete on public.quality_rasd for delete using (public.q_role() = 'admin');

create index if not exists quality_rasd_month on public.quality_rasd (month);
