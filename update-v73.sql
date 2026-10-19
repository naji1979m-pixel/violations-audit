-- تحديث v73 — يُشغَّل مرة واحدة في Supabase ← SQL Editor
-- (1) جودة الرصد: تاريخ أول تقييم حتى يُحتسب التقييم مرة واحدة
alter table public.quality_rasd add column if not exists eval_first_at timestamptz;
update public.quality_rasd set eval_first_at = eval_at where eval_first_at is null and score is not null;

-- (2) الأكاديمية: حفظ التقدم وحساب نتيجة الاختبار من الخادم فقط
create or replace function public.q_course_progress(p_course uuid, p_action text, p_answers jsonb default null)
returns public.quality_course_progress
language plpgsql security definer set search_path = public as $$
declare u public.quality_users; c public.quality_courses; r public.quality_course_progress;
        q jsonb; n int; ok int := 0; i int; sc numeric; pm int;
begin
  select * into u from public.quality_users where id = auth.uid() and active;
  if u.id is null then raise exception 'غير مصرح'; end if;
  select * into c from public.quality_courses where id = p_course;
  if c.id is null or (not c.active and not public.q_acad_editor()) then raise exception 'الدورة غير متاحة'; end if;

  insert into public.quality_course_progress (user_id, course_id, full_name, job, sector)
  values (u.id, c.id, u.full_name, u.job, u.sector)
  on conflict (user_id, course_id) do update
    set full_name = excluded.full_name, job = excluded.job, sector = excluded.sector
  returning * into r;

  q := coalesce(c.quiz, '[]'::jsonb); n := jsonb_array_length(q); pm := coalesce(c.pass_mark, 80);

  if p_action = 'video' then
    update public.quality_course_progress
       set video_done = true,
           completed_at = case when n = 0 then coalesce(completed_at, now()) else completed_at end,
           updated_at = now()
     where user_id = u.id and course_id = c.id returning * into r;

  elsif p_action = 'finish' then
    if n > 0 then raise exception 'هذه الدورة تتطلب اجتياز الاختبار'; end if;
    update public.quality_course_progress
       set video_done = true, completed_at = coalesce(completed_at, now()), updated_at = now()
     where user_id = u.id and course_id = c.id returning * into r;

  elsif p_action = 'quiz' then
    if n = 0 then raise exception 'لا يوجد اختبار لهذه الدورة'; end if;
    if p_answers is null or jsonb_typeof(p_answers) <> 'array' or jsonb_array_length(p_answers) <> n then
      raise exception 'أجب عن جميع الأسئلة'; end if;
    for i in 0 .. n - 1 loop
      if coalesce((p_answers ->> i)::int, -1) = coalesce((q -> i ->> 'a')::int, -2) then ok := ok + 1; end if;
    end loop;
    sc := round(ok::numeric / n * 1000) / 10;
    update public.quality_course_progress
       set score = sc,
           best = greatest(coalesce(best, 0), sc),
           attempts = attempts + 1,
           passed = passed or sc >= pm,
           completed_at = case when passed or sc >= pm then coalesce(completed_at, now()) else completed_at end,
           updated_at = now()
     where user_id = u.id and course_id = c.id returning * into r;
  end if;
  return r;
end $$;
revoke execute on function public.q_course_progress(uuid, text, jsonb) from anon;
grant execute on function public.q_course_progress(uuid, text, jsonb) to authenticated;

-- منع تعديل النتائج مباشرة: الكتابة عبر الدالة فقط (القراءة كما هي، والحذف لمدير النظام)
drop policy if exists qp_insert on public.quality_course_progress;
drop policy if exists qp_update on public.quality_course_progress;
