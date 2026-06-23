create extension if not exists "uuid-ossp";

create table if not exists public.canvas_pages (
  id uuid primary key,
  canvas_id uuid not null references public.canvases(id) on delete cascade,
  content_canvas_id uuid not null default uuid_generate_v4(),
  user_id uuid references auth.users on delete cascade not null,
  name text not null default 'Page 1',
  x double precision not null default 0,
  y double precision not null default 0,
  width double precision not null default 800,
  height double precision not null default 600,
  order_index integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);

alter table public.canvas_pages add column if not exists content_canvas_id uuid;
update public.canvas_pages
set content_canvas_id = canvas_id
where content_canvas_id is null;
alter table public.canvas_pages alter column content_canvas_id set not null;
alter table public.canvas_pages alter column content_canvas_id set default uuid_generate_v4();

alter table public.canvas_pages enable row level security;

drop policy if exists "Users can CRUD own canvas pages" on public.canvas_pages;
create policy "Users can CRUD own canvas pages" on public.canvas_pages for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists idx_canvas_pages_canvas_id on public.canvas_pages(canvas_id);
create index if not exists idx_canvas_pages_content_canvas_id on public.canvas_pages(content_canvas_id);
create index if not exists idx_canvas_pages_user_id on public.canvas_pages(user_id);
create index if not exists idx_canvas_pages_canvas_order on public.canvas_pages(canvas_id, order_index);
