create extension if not exists "uuid-ossp";

create table if not exists public.element_groups (
  id uuid primary key,
  canvas_id uuid not null references public.canvases(id) on delete cascade,
  user_id uuid references auth.users on delete cascade not null,
  name text not null default 'Group',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);

alter table public.element_groups enable row level security;

drop policy if exists "Users can CRUD own element groups" on public.element_groups;
create policy "Users can CRUD own element groups" on public.element_groups for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists idx_element_groups_canvas_id on public.element_groups(canvas_id);
create index if not exists idx_element_groups_user_id on public.element_groups(user_id);

do $$
declare
  table_name text;
  index_name text;
begin
  foreach table_name in array array[
    'text_elements',
    'sticky_notes',
    'todo_lists',
    'shapes',
    'image_elements',
    'pdf_elements',
    'table_elements',
    'audio_elements',
    'youtube_elements',
    'drawings',
    'symbol_elements',
    'connectors'
  ] loop
    if to_regclass('public.' || table_name) is not null then
      execute format(
        'alter table public.%I add column if not exists group_id uuid references public.element_groups(id) on delete set null',
        table_name
      );

      index_name := 'idx_' || table_name || '_group_id';
      execute format(
        'create index if not exists %I on public.%I(group_id)',
        index_name,
        table_name
      );
    end if;
  end loop;
end $$;
