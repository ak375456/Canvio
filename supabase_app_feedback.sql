-- Canvio anonymous feedback backend
--
-- Before running this file, create this private bucket in Supabase Dashboard:
--   Storage -> New bucket
--   Name: feedback-images
--   Public bucket: OFF
--   File size limit: 8 MB
--   Allowed MIME types: image/jpeg, image/png

create table if not exists public.app_feedback (
  id uuid primary key,
  category text not null
    check (category in ('improvement', 'bug', 'other')),
  message text not null
    check (char_length(btrim(message)) between 5 and 4000),
  image_path text,
  platform text not null
    check (char_length(platform) between 1 and 40),
  app_version text not null
    check (char_length(app_version) between 1 and 40),
  build_number text not null
    check (char_length(build_number) between 1 and 40),
  os_version text not null
    check (char_length(os_version) between 1 and 200),
  device_model text not null
    check (char_length(device_model) between 1 and 100),
  created_at timestamptz not null default now(),
  constraint app_feedback_image_path_matches_id check (
    image_path is null
    or image_path in (
      'submissions/' || id::text || '/attachment.jpg',
      'submissions/' || id::text || '/attachment.png'
    )
  )
);

alter table public.app_feedback enable row level security;

revoke all on table public.app_feedback from anon, authenticated;
grant insert (
  id,
  category,
  message,
  image_path,
  platform,
  app_version,
  build_number,
  os_version,
  device_model
) on table public.app_feedback to anon, authenticated;

drop policy if exists "Anyone can submit anonymous app feedback" on public.app_feedback;
create policy "Anyone can submit anonymous app feedback"
on public.app_feedback
for insert
to anon, authenticated
with check (
  category in ('improvement', 'bug', 'other')
  and char_length(btrim(message)) between 5 and 4000
  and (
    image_path is null
    or image_path in (
      'submissions/' || id::text || '/attachment.jpg',
      'submissions/' || id::text || '/attachment.png'
    )
  )
);

-- Upload-only access. The bucket stays private and the app cannot list or read
-- feedback images. They remain viewable by the project owner in Supabase.
drop policy if exists "Anyone can upload a feedback image" on storage.objects;
create policy "Anyone can upload a feedback image"
on storage.objects
for insert
to anon, authenticated
with check (
  bucket_id = 'feedback-images'
  and name ~ '^submissions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/attachment\.(jpg|png)$'
);

create index if not exists app_feedback_created_at_idx
  on public.app_feedback (created_at desc);

comment on table public.app_feedback is
  'Anonymous in-app improvement, bug, and general feedback. No Canvio account identity columns are stored.';
