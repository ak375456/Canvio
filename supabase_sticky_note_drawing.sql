-- Canvio: embedded PencilKit drawings for sticky notes
--
-- Run this once in the Supabase SQL Editor. The app stores PKDrawing's
-- compact binary representation as base64 so the ink can use the existing
-- sticky_notes upsert, offline queue, and last-write-wins sync flow.

begin;

alter table public.sticky_notes
  add column if not exists drawing_data text;

update public.sticky_notes
set drawing_data = ''
where drawing_data is null;

alter table public.sticky_notes
  alter column drawing_data set default '',
  alter column drawing_data set not null;

comment on column public.sticky_notes.drawing_data is
  'Base64-encoded PencilKit PKDrawing data for ink embedded in this sticky note.';

commit;
