-- Ponder / Canvio rich text for canvas text elements
--
-- Run this in Supabase SQL Editor after the base text_elements table exists.
-- Existing text rows are backfilled into a single styled run, so old canvases
-- keep rendering exactly as before.

begin;

alter table public.text_elements
  add column if not exists rich_text jsonb;

update public.text_elements
set rich_text = jsonb_build_object(
  'version', 1,
  'runs',
    case
      when coalesce(text, '') = '' then '[]'::jsonb
      else jsonb_build_array(
        jsonb_build_object(
          'text', text,
          'attrs', jsonb_build_object(
            'fontName', coalesce(nullif(font_name, ''), 'system'),
            'fontSize', coalesce(font_size, 16),
            'bold', coalesce(is_bold, false),
            'italic', coalesce(is_italic, false),
            'underline', coalesce(is_underline, false),
            'colorName', coalesce(nullif(color_name, ''), 'primary')
          )
        )
      )
    end,
  'paragraph', jsonb_build_object(
    'alignmentRaw',
    case alignment_raw
      when 'center' then 'center'
      when 'trailing' then 'trailing'
      else 'leading'
    end
  )
)
where rich_text is null
   or jsonb_typeof(rich_text) <> 'object'
   or coalesce(jsonb_typeof(rich_text -> 'runs') = 'array', false) = false
   or coalesce(jsonb_typeof(rich_text -> 'paragraph') = 'object', false) = false
   or case
      when coalesce(jsonb_typeof(rich_text -> 'runs') = 'array', false)
      then jsonb_array_length(rich_text -> 'runs') = 0 and coalesce(text, '') <> ''
      else false
   end;

alter table public.text_elements
  alter column rich_text set default
  '{
    "version": 1,
    "runs": [],
    "paragraph": {
      "alignmentRaw": "leading"
    }
  }'::jsonb;

update public.text_elements
set rich_text = '{
  "version": 1,
  "runs": [],
  "paragraph": {
    "alignmentRaw": "leading"
  }
}'::jsonb
where rich_text is null;

alter table public.text_elements
  alter column rich_text set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'text_elements_rich_text_shape'
      and conrelid = 'public.text_elements'::regclass
  ) then
    alter table public.text_elements
      add constraint text_elements_rich_text_shape
      check (
        jsonb_typeof(rich_text) = 'object'
        and coalesce(jsonb_typeof(rich_text -> 'runs') = 'array', false)
        and coalesce(jsonb_typeof(rich_text -> 'paragraph') = 'object', false)
      );
  end if;
end
$$;

comment on column public.text_elements.rich_text is
  'Versioned rich text document. Store plain searchable text in text; store per-range text styling here.';

commit;
