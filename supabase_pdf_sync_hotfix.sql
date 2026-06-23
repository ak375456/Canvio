-- Confirmed hotfix for PDF page tiles created by the current Swift client.
-- Safe to run more than once in Supabase SQL Editor.

begin;

alter table public.pdf_page_elements
  add column if not exists pdf_file_name text not null default '',
  add column if not exists original_name text not null default 'Document';

-- Populate metadata for any page rows created by an earlier schema version.
update public.pdf_page_elements as page
set
  pdf_file_name = case
    when page.pdf_file_name = '' then document.pdf_file_name
    else page.pdf_file_name
  end,
  original_name = case
    when page.original_name = '' or page.original_name = 'Document'
      then document.original_name
    else page.original_name
  end
from public.pdf_documents as document
where document.id = page.document_id;

commit;

-- Ask PostgREST to refresh immediately instead of waiting for schema-cache
-- invalidation. This is what resolves the "column not found in schema cache"
-- response after the ALTER TABLE above.
notify pgrst, 'reload schema';
