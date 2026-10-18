-- =====================================================================
-- أكاديمية إدارة المخالفات — يُشغَّل مرة واحدة في Supabase ← SQL Editor
-- =====================================================================

-- 1) صلاحية «متدرب» + نوعه (مأمور ضبط / مدير رقابة)
alter table public.quality_users add column if not exists job text;

do $$
declare c record; r text;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.quality_users'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%role%' loop
    execute format('alter table public.quality_users drop constraint %I', c.conname);
  end loop;
  select string_agg(quote_literal(x), ',') into r from (
    select unnest(array['admin','exec','manager','staff','clerk','viewer','trainee']) x
    union select distinct role from public.quality_users where role is not null) t;
  execute 'alter table public.quality_users add constraint quality_users_role_check check (role in (' || r || '))';
end $$;

-- المتدرب لا يرى بيانات المخالفات ولا التدقيق — الأكاديمية فقط
create or replace function public.q_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.quality_users where id = auth.uid() and active and role <> 'trainee'
$$;

create or replace function public.q_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.quality_users where id = auth.uid() and active)
$$;

create or replace function public.q_is_hq() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.quality_users
    where id = auth.uid() and active and role <> 'trainee'
      and (role in ('admin','exec') or coalesce(sector,'') like '%المركز الرئيسي%'))
$$;

-- فريق تجهيز الأكاديمية: مدير النظام + نايف البقمي + حسين الرمضان (+ المركز الرئيسي بعد الافتتاح)
create or replace function public.q_acad_editor() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.quality_users
    where id = auth.uid() and active and role <> 'trainee'
      and (role = 'admin'
           or (full_name like '%نايف%' and full_name like '%البقمي%')
           or (full_name like '%حسين%' and full_name like '%الرمضان%')))
  or public.q_is_hq()
$$;

-- تعيين حساب كمتدرب (لمدير النظام فقط)
create or replace function public.q_set_trainee(p_user uuid, p_job text, p_sector text, p_full_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.quality_users where id = auth.uid() and active and role = 'admin') then
    raise exception 'غير مصرح'; end if;
  if p_job not in ('o','m') then raise exception 'نوع المتدرب غير صحيح'; end if;
  update public.quality_users
     set role = 'trainee', job = p_job, sector = nullif(trim(p_sector), ''),
         full_name = coalesce(nullif(trim(p_full_name), ''), full_name)
   where id = p_user;
end $$;
revoke execute on function public.q_set_trainee(uuid,text,text,text) from anon;

-- 2) الدورات
create table if not exists public.quality_courses (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  summary    text,
  category   text,
  audience   text not null default 'all' check (audience in ('all','o','m')),
  item       text,
  minutes    int,
  video_url  text,
  body       text,
  checklist  jsonb not null default '[]'::jsonb,
  sample     text,
  quiz       jsonb not null default '[]'::jsonb,
  pass_mark  int not null default 80,
  mandatory  boolean not null default false,
  active     boolean not null default false,
  sort       int not null default 0,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 3) سجل التدريب
create table if not exists public.quality_course_progress (
  user_id      uuid not null references public.quality_users(id) on delete cascade,
  course_id    uuid not null references public.quality_courses(id) on delete cascade,
  full_name    text,
  job          text,
  sector       text,
  video_done   boolean not null default false,
  score        numeric,
  best         numeric,
  passed       boolean not null default false,
  attempts     int not null default 0,
  started_at   timestamptz default now(),
  completed_at timestamptz,
  updated_at   timestamptz not null default now(),
  primary key (user_id, course_id)
);

alter table public.quality_courses enable row level security;
alter table public.quality_course_progress enable row level security;

drop policy if exists qc_select on public.quality_courses;
drop policy if exists qc_insert on public.quality_courses;
drop policy if exists qc_update on public.quality_courses;
drop policy if exists qc_delete on public.quality_courses;
create policy qc_select on public.quality_courses for select using (public.q_member() and (active or public.q_acad_editor()));
create policy qc_insert on public.quality_courses for insert with check (public.q_acad_editor());
create policy qc_update on public.quality_courses for update using (public.q_acad_editor());
create policy qc_delete on public.quality_courses for delete using (public.q_acad_editor());

drop policy if exists qp_select on public.quality_course_progress;
drop policy if exists qp_insert on public.quality_course_progress;
drop policy if exists qp_update on public.quality_course_progress;
drop policy if exists qp_delete on public.quality_course_progress;
create policy qp_select on public.quality_course_progress for select using (user_id = auth.uid() or public.q_role() is not null);
create policy qp_insert on public.quality_course_progress for insert with check (user_id = auth.uid() and public.q_member());
create policy qp_update on public.quality_course_progress for update using (user_id = auth.uid());
create policy qp_delete on public.quality_course_progress for delete using (public.q_role() = 'admin');

-- 4) دورات مبدئية (مسودات — راجعها وعدّلها ثم انشرها من «إدارة الدورات»)
insert into public.quality_courses (title, summary, category, audience, minutes, body, checklist, sample, quiz, mandatory, active, sort)
select * from (values
 ('مدخل إلى جودة الرصد', 'لماذا تُسترجع المخالفات، وكيف تُقاس جودة الرصد شهرياً', 'معايير جودة الرصد', 'all', 8,
  $b$تقيس إدارة المخالفات **جودة الرصد** شهرياً بسحب عينة 25% من المخالفات المرسلة للهيئة، وتقييمها على ستة معايير:
- الفترة الزمنية لرصد المخالفة (10%)
- جودة الصور (20%)
- وضوح الوصف (20%)
- جودة احتساب المنفعة المفقودة (15%)
- جودة احتساب إصلاح الضرر (15%)
- دقة البيانات المدخلة في المنصة (20%)

المخالفة **مقبولة** إذا حصلت على 80% فأكثر. كل معيار لا يتجاوزه الملف يُخصم وزنه كاملاً.$b$,
  '["أعرف المعايير الستة وأوزانها","أعرف أن المقبولة 80% فأكثر","أراجع ملفي قبل الإرسال على المعايير الستة"]'::jsonb, null,
  '[{"q":"ما الحد الأدنى لتكون المخالفة مقبولة في جودة الرصد؟","o":["60%","70%","80%","100%"],"a":2},{"q":"أي معيارين وزنهما الأعلى مع دقة البيانات (20%)؟","o":["جودة الصور ووضوح الوصف","الفترة الزمنية والمنفعة المفقودة","إصلاح الضرر والفترة الزمنية",""],"a":0},{"q":"كم نسبة العينة الشهرية من المخالفات المرسلة للهيئة؟","o":["10%","25%","50%","100%"],"a":1}]'::jsonb, true, false, 1),
 ('جودة الصور', 'كيف تلتقط صوراً تثبت المخالفة بلا لبس', 'معايير جودة الرصد', 'o', 10,
  $b$الصورة هي الدليل الأول أمام الهيئة. الصورة الجيدة تُظهر **المخالفة نفسها** و**مكانها** و**ما يربطها بالعقار أو العداد**.
- صورة عامة توضح الموقع والعقار
- صورة قريبة توضح المخالفة بوضوح
- صورة للعداد أو رقمه أو الوصلة عند الحاجة
- إضاءة كافية، بدون اهتزاز أو حجب$b$,
  '["صورة عامة للموقع","صورة قريبة للمخالفة","العداد أو رقمه ظاهر عند الحاجة","الصور واضحة وغير مهتزة","لا توجد صور مكررة أو لا علاقة لها بالمخالفة"]'::jsonb, null,
  '[{"q":"أي مجموعة صور أفضل لإثبات مخالفة؟","o":["صورة واحدة قريبة فقط","صورة عامة + صورة قريبة + ما يربطها بالعقار","صور كثيرة مكررة",""],"a":1},{"q":"صورة مهتزة لا تظهر فيها المخالفة بوضوح:","o":["تكفي إذا كان الوصف جيداً","تُعاد قبل الإرسال","تُرسل وتُشرح لاحقاً",""],"a":1}]'::jsonb, true, false, 2),
 ('وضوح الوصف', 'كتابة وصف يجيب: ماذا، أين، كيف، وما الدليل', 'معايير جودة الرصد', 'o', 10,
  $b$الوصف الواضح يُغني المدقق والهيئة عن السؤال. اكتب **ماذا رصدت، وأين، وكيف تحققت منها، وما يثبتها**، بجمل قصيرة ومحددة، وبما يطابق البند المختار.$b$,
  '["يذكر نوع المخالفة بما يطابق البند","يحدد الموقع بدقة","يذكر طريقة الاكتشاف أو التحقق","يشير إلى الصور المرفقة","خالٍ من العبارات العامة مثل «توجد مخالفة»"]'::jsonb,
  $s$أثناء الجولة الميدانية بتاريخ (...) في حي (...)، رُصدت وصلة مياه غير نظامية من الشبكة العامة إلى العقار رقم (...) دون عداد، بقطر (...). تم التحقق بفحص الموقع وتتبّع الوصلة، والصور المرفقة توضح الوصلة وموقعها والعقار.$s$,
  '[{"q":"أي وصف أفضل؟","o":["توجد مخالفة في الموقع","رُصدت وصلة غير نظامية من الشبكة إلى العقار رقم (...) دون عداد، والصور توضح ذلك","مخالفة توصيل",""],"a":1}]'::jsonb, true, false, 3),
 ('جودة احتساب المنفعة المفقودة', 'تطبيق آلية الاحتساب المعتمدة وإرفاقها', 'معايير جودة الرصد', 'all', 12,
  $b$احتساب المنفعة المفقودة يجب أن يتبع **الآلية المعتمدة**، بمدخلات صحيحة ووحدات صحيحة، وأن يُرفق ملف الاحتساب مع المخالفة.
أضف هنا شرح الآلية المعتمدة لديكم بالتفصيل.$b$,
  '["استخدام نموذج الاحتساب المعتمد","المدخلات مطابقة لبيانات المخالفة","الوحدات صحيحة","ملف الاحتساب مرفق"]'::jsonb, null, '[]'::jsonb, false, false, 4),
 ('جودة احتساب إصلاح الضرر', 'تقدير تكاليف الإصلاح بدقة وتوثيقها', 'معايير جودة الرصد', 'all', 12,
  $b$تكاليف إصلاح الضرر تُحسب وفق **قائمة الأسعار المعتمدة**، وتشمل البنود الفعلية للضرر فقط، مع إرفاق ما يثبتها.
أضف هنا شرح الآلية المعتمدة لديكم.$b$,
  '["البنود تطابق الضرر الفعلي","الأسعار من القائمة المعتمدة","الحساب صحيح","المستندات مرفقة"]'::jsonb, null, '[]'::jsonb, false, false, 5),
 ('دقة البيانات المدخلة في المنصة', 'أخطاء البيانات الشائعة وكيف تتجنبها', 'معايير جودة الرصد', 'all', 8,
  $b$الخطأ في البيانات قد يُسقط المخالفة حتى لو كانت ثابتة. راجع كل حقل قبل الإرسال.$b$,
  '["اسم المخالف وهويته صحيحة","الإحداثيات تطابق الموقع","البند المختار يطابق الوصف والصور","التواريخ صحيحة","لا توجد حقول إلزامية فارغة"]'::jsonb, null,
  '[{"q":"البند المختار لا يطابق الصور والوصف. ما الإجراء؟","o":["يُرسل كما هو","يُصحح البند قبل الإرسال","يُكتب في الملاحظات فقط",""],"a":1}]'::jsonb, true, false, 6),
 ('الفترة الزمنية لرصد المخالفة', 'الالتزام بالمدد المحددة من الرصد حتى الإرسال', 'معايير جودة الرصد', 'all', 6,
  $b$التأخير في تسجيل المخالفة أو إرسالها يضعف الملف. سجّل المخالفة في يوم رصدها، واستكمل متطلباتها ضمن المدة المحددة لديكم.
أضف هنا المدد المعتمدة.$b$,
  '["تسجيل المخالفة يوم رصدها","استكمال المتطلبات ضمن المدة","عدم ترك المخالفة دون إرسال"]'::jsonb, null, '[]'::jsonb, false, false, 7),
 ('تدقيق الملف قبل الاعتماد', 'دليل مدير الرقابة لمراجعة ملف المخالفة قبل اعتماده للهيئة', 'معايير جودة الرصد', 'm', 10,
  $b$مدير الرقابة هو خط الدفاع الأخير قبل الهيئة. راجع الملف على المعايير الستة، ولا تعتمد ملفاً ناقصاً؛ أعده للمأمور مع ملاحظة واضحة.$b$,
  '["الصور كافية وواضحة","الوصف يطابق البند","احتساب المنفعة وإصلاح الضرر مرفق وصحيح","البيانات مكتملة ودقيقة","ملاحظة الإعادة واضحة ومحددة"]'::jsonb, null,
  '[{"q":"وجدت أن احتساب المنفعة المفقودة غير مرفق. ما الإجراء؟","o":["أعتمد الملف وأرفقه لاحقاً","أعيد الملف للمأمور بملاحظة محددة","أرفض المخالفة نهائياً",""],"a":1}]'::jsonb, true, false, 8)
) v(title, summary, category, audience, minutes, body, checklist, sample, quiz, mandatory, active, sort)
where not exists (select 1 from public.quality_courses);
