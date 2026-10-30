-- عداد الاستخدام اليومي للقراءة الذكية للصور (تكتب فيه الوظيفة السحابية read-photo فقط)
create table if not exists public.quality_ai_photo_usage (
  user_id uuid not null,
  day date not null,
  n integer not null default 0,
  updated_at timestamptz default now(),
  primary key (user_id, day)
);
alter table public.quality_ai_photo_usage enable row level security;
