-- Ponder / Canvio PDF workspace schema
--
-- Run this after the existing canvases, pdf_elements, text_elements, and
-- element_groups migrations. It preserves existing PDF cards and introduces a
-- document asset layer so page tiles and annotations can outlive a card.

begin;

create extension if not exists "uuid-ossp";

-- MARK: PDF document assets

create table if not exists public.pdf_documents (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references auth.users(id) on delete cascade not null,
  pdf_file_name text not null,
  thumbnail_file_name text not null,
  original_name text not null default 'Document',
  page_count integer not null default 1 check (page_count > 0),
  file_size_bytes bigint,
  sha256 text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  unique (user_id, pdf_file_name)
);

-- Backfill one document asset for every existing PDF card. Existing IDs are
-- reused only during migration, which makes the operation deterministic.
insert into public.pdf_documents (
  id,
  user_id,
  pdf_file_name,
  thumbnail_file_name,
  original_name,
  page_count,
  created_at,
  updated_at,
  is_deleted
)
select
  id,
  user_id,
  pdf_file_name,
  thumbnail_file_name,
  original_name,
  greatest(page_count, 1),
  created_at,
  updated_at,
  is_deleted
from public.pdf_elements
on conflict (id) do nothing;

alter table public.pdf_elements
  add column if not exists document_id uuid;

update public.pdf_elements
set document_id = id
where document_id is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pdf_elements_document_id_fkey'
      and conrelid = 'public.pdf_elements'::regclass
  ) then
    alter table public.pdf_elements
      add constraint pdf_elements_document_id_fkey
      foreign key (document_id)
      references public.pdf_documents(id)
      on delete cascade;
  end if;
end
$$;

alter table public.pdf_elements
  alter column document_id set not null;

-- MARK: Individual PDF pages placed on a canvas

create table if not exists public.pdf_page_elements (
  id uuid primary key default uuid_generate_v4(),
  document_id uuid not null references public.pdf_documents(id) on delete cascade,
  canvas_id uuid not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  pdf_file_name text not null default '',
  original_name text not null default 'Document',
  page_index integer not null check (page_index >= 0),

  x double precision not null default 0,
  y double precision not null default 0,
  width double precision not null default 420 check (width > 0),
  height double precision not null default 560 check (height > 0),
  rotation double precision not null default 0,

  -- Normalized page coordinates. (0,0,1,1) displays the full page.
  crop_x double precision not null default 0 check (crop_x >= 0 and crop_x <= 1),
  crop_y double precision not null default 0 check (crop_y >= 0 and crop_y <= 1),
  crop_width double precision not null default 1 check (crop_width > 0 and crop_width <= 1),
  crop_height double precision not null default 1 check (crop_height > 0 and crop_height <= 1),

  shows_annotations boolean not null default true,
  z_index integer not null default 0,
  group_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,

  constraint pdf_page_elements_crop_x_range
    check (crop_x + crop_width <= 1.000001),
  constraint pdf_page_elements_crop_y_range
    check (crop_y + crop_height <= 1.000001)
);

alter table public.pdf_page_elements
  add column if not exists pdf_file_name text not null default '',
  add column if not exists original_name text not null default 'Document';

comment on table public.pdf_page_elements is
  'Canvas placements of individual PDF pages or non-destructive cropped regions.';

-- MARK: Text highlights kept outside the source PDF

create table if not exists public.pdf_highlights (
  id uuid primary key default uuid_generate_v4(),
  document_id uuid not null references public.pdf_documents(id) on delete cascade,
  canvas_id uuid not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  page_index integer not null check (page_index >= 0),
  selected_text text not null default '',

  -- Array of normalized page rectangles:
  -- [{"x":0.12,"y":0.24,"width":0.42,"height":0.03}, ...]
  rects jsonb not null default '[]'::jsonb
    check (jsonb_typeof(rects) = 'array'),
  color_hex text not null default '#FFD60A',
  opacity double precision not null default 0.35
    check (opacity >= 0 and opacity <= 1),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);

comment on table public.pdf_highlights is
  'App-owned highlight overlays. These rows are never written into the PDF file.';

-- MARK: PencilKit overlay, one independently syncable layer per PDF page

create table if not exists public.pdf_ink_layers (
  id uuid primary key default uuid_generate_v4(),
  document_id uuid not null references public.pdf_documents(id) on delete cascade,
  canvas_id uuid not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  page_index integer not null check (page_index >= 0),

  -- Base64 PKDrawing.dataRepresentation(), matching the app's drawings table.
  drawing_data text not null default '',
  coordinate_width double precision not null default 1 check (coordinate_width > 0),
  coordinate_height double precision not null default 1 check (coordinate_height > 0),
  format_version integer not null default 1 check (format_version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false,

  unique (document_id, canvas_id, page_index)
);

comment on table public.pdf_ink_layers is
  'PencilKit drawings stored separately from the source PDF, one layer per page and canvas.';

-- MARK: Cross-device reading position and reader preferences

create table if not exists public.pdf_reading_states (
  id uuid primary key default uuid_generate_v4(),
  document_id uuid not null references public.pdf_documents(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade not null,
  current_page_index integer not null default 0 check (current_page_index >= 0),
  scroll_progress double precision not null default 0
    check (scroll_progress >= 0 and scroll_progress <= 1),
  zoom_scale double precision not null default 1 check (zoom_scale > 0),
  display_mode_raw text not null default 'paged'
    check (display_mode_raw in ('paged', 'continuous', 'book')),
  sidebar_visible boolean not null default true,
  last_opened_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (document_id, user_id)
);

-- Extracted PDF text remains a normal text card. These nullable fields preserve
-- its source so "Open source" can return to the exact page and selection.
alter table public.text_elements
  add column if not exists source_pdf_document_id uuid
    references public.pdf_documents(id) on delete set null,
  add column if not exists source_pdf_page_index integer,
  add column if not exists source_pdf_rects jsonb;

-- MARK: Indexes

create index if not exists idx_pdf_documents_user_updated
  on public.pdf_documents(user_id, updated_at);

create index if not exists idx_pdf_elements_document_id
  on public.pdf_elements(document_id);

create index if not exists idx_pdf_page_elements_canvas_user
  on public.pdf_page_elements(canvas_id, user_id, updated_at);
create index if not exists idx_pdf_page_elements_document_page
  on public.pdf_page_elements(document_id, page_index);
create index if not exists idx_pdf_page_elements_group_id
  on public.pdf_page_elements(group_id);

create index if not exists idx_pdf_highlights_canvas_document_page
  on public.pdf_highlights(canvas_id, document_id, page_index, updated_at);

create index if not exists idx_pdf_ink_layers_canvas_document_page
  on public.pdf_ink_layers(canvas_id, document_id, page_index, updated_at);

create index if not exists idx_pdf_reading_states_user_updated
  on public.pdf_reading_states(user_id, updated_at);

create index if not exists idx_text_elements_source_pdf
  on public.text_elements(source_pdf_document_id, source_pdf_page_index)
  where source_pdf_document_id is not null;

-- MARK: updated_at triggers

create or replace function public.set_pdf_workspace_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_pdf_documents_updated_at on public.pdf_documents;
create trigger set_pdf_documents_updated_at
before update on public.pdf_documents
for each row execute function public.set_pdf_workspace_updated_at();

drop trigger if exists set_pdf_page_elements_updated_at on public.pdf_page_elements;
create trigger set_pdf_page_elements_updated_at
before update on public.pdf_page_elements
for each row execute function public.set_pdf_workspace_updated_at();

drop trigger if exists set_pdf_highlights_updated_at on public.pdf_highlights;
create trigger set_pdf_highlights_updated_at
before update on public.pdf_highlights
for each row execute function public.set_pdf_workspace_updated_at();

drop trigger if exists set_pdf_ink_layers_updated_at on public.pdf_ink_layers;
create trigger set_pdf_ink_layers_updated_at
before update on public.pdf_ink_layers
for each row execute function public.set_pdf_workspace_updated_at();

drop trigger if exists set_pdf_reading_states_updated_at on public.pdf_reading_states;
create trigger set_pdf_reading_states_updated_at
before update on public.pdf_reading_states
for each row execute function public.set_pdf_workspace_updated_at();

-- MARK: Row-level security

alter table public.pdf_documents enable row level security;
alter table public.pdf_page_elements enable row level security;
alter table public.pdf_highlights enable row level security;
alter table public.pdf_ink_layers enable row level security;
alter table public.pdf_reading_states enable row level security;

drop policy if exists "Users can CRUD own PDF documents" on public.pdf_documents;
create policy "Users can CRUD own PDF documents"
on public.pdf_documents for all to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can CRUD own PDF page elements" on public.pdf_page_elements;
create policy "Users can CRUD own PDF page elements"
on public.pdf_page_elements for all to authenticated
using (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.pdf_documents d
    where d.id = pdf_page_elements.document_id
      and d.user_id = (select auth.uid())
  )
)
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.pdf_documents d
    where d.id = pdf_page_elements.document_id
      and d.user_id = (select auth.uid())
  )
);

drop policy if exists "Users can CRUD own PDF highlights" on public.pdf_highlights;
create policy "Users can CRUD own PDF highlights"
on public.pdf_highlights for all to authenticated
using (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.pdf_documents d
    where d.id = pdf_highlights.document_id
      and d.user_id = (select auth.uid())
  )
)
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.pdf_documents d
    where d.id = pdf_highlights.document_id
      and d.user_id = (select auth.uid())
  )
);

drop policy if exists "Users can CRUD own PDF ink layers" on public.pdf_ink_layers;
create policy "Users can CRUD own PDF ink layers"
on public.pdf_ink_layers for all to authenticated
using (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.pdf_documents d
    where d.id = pdf_ink_layers.document_id
      and d.user_id = (select auth.uid())
  )
)
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.pdf_documents d
    where d.id = pdf_ink_layers.document_id
      and d.user_id = (select auth.uid())
  )
);

drop policy if exists "Users can CRUD own PDF reading state" on public.pdf_reading_states;
create policy "Users can CRUD own PDF reading state"
on public.pdf_reading_states for all to authenticated
using (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.pdf_documents d
    where d.id = pdf_reading_states.document_id
      and d.user_id = (select auth.uid())
  )
)
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.pdf_documents d
    where d.id = pdf_reading_states.document_id
      and d.user_id = (select auth.uid())
  )
);

grant select, insert, update, delete on
  public.pdf_documents,
  public.pdf_page_elements,
  public.pdf_highlights,
  public.pdf_ink_layers,
  public.pdf_reading_states
to authenticated;

-- Publish overlay changes for live multi-device updates. The app can still use
-- its existing offline queue + pull-on-launch path before Realtime is wired in.
do $$
declare
  table_name text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach table_name in array array[
      'pdf_documents',
      'pdf_page_elements',
      'pdf_highlights',
      'pdf_ink_layers',
      'pdf_reading_states'
    ] loop
      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = table_name
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          table_name
        );
      end if;
    end loop;
  end if;
end
$$;

commit;
