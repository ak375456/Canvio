-- Canvio sync tombstone retention and cleanup
--
-- Sync rows remain soft-deleted for 30 days so another device can observe the
-- deletion. After that retention window, this migration permanently removes
-- the tombstones and any content belonging to an expired canvas or page.

begin;

create extension if not exists pg_cron with schema pg_catalog;

create or replace function public.purge_canvio_sync_tombstones(
  retention_period interval default interval '30 days'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  cutoff timestamptz;
  sync_table text;
  affected bigint;
  deleted_counts jsonb := '{}'::jsonb;
begin
  if retention_period < interval '1 day' then
    raise exception 'Tombstone retention must be at least one day';
  end if;

  cutoff := clock_timestamp() - retention_period;

  -- A deleted canvas only needs one tombstone for other devices to remove the
  -- entire local canvas. Its element rows may therefore still be active. Keep
  -- their content IDs so those related rows are physically removed together.
  create temporary table if not exists pg_temp.canvio_expired_canvas_ids (
    id uuid primary key
  ) on commit drop;
  truncate pg_temp.canvio_expired_canvas_ids;

  insert into pg_temp.canvio_expired_canvas_ids (id)
  select id
  from public.canvases
  where is_deleted is true
    and updated_at < cutoff;

  create temporary table if not exists pg_temp.canvio_expired_content_ids (
    id uuid primary key
  ) on commit drop;
  truncate pg_temp.canvio_expired_content_ids;

  insert into pg_temp.canvio_expired_content_ids (id)
  select id from pg_temp.canvio_expired_canvas_ids
  on conflict do nothing;

  if to_regclass('public.canvas_pages') is not null then
    insert into pg_temp.canvio_expired_content_ids (id)
    select content_canvas_id
    from public.canvas_pages
    where canvas_id in (select id from pg_temp.canvio_expired_canvas_ids)
       or (is_deleted is true and updated_at < cutoff)
    on conflict do nothing;
  end if;

  -- Remove nested children before their parent cards. These rows do not carry
  -- canvas_id themselves, so they cannot be handled by the generic loop below.
  if to_regclass('public.todo_tasks') is not null
     and to_regclass('public.todo_lists') is not null then
    delete from public.todo_tasks task
    using public.todo_lists list
    where task.list_id = list.id
      and list.canvas_id in (select id from pg_temp.canvio_expired_content_ids);
    get diagnostics affected = row_count;
    deleted_counts := deleted_counts || jsonb_build_object('todo_tasks', affected);
  end if;

  if to_regclass('public.table_cells') is not null
     and to_regclass('public.table_elements') is not null then
    delete from public.table_cells cell
    using public.table_elements table_element
    where cell.table_id = table_element.id
      and table_element.canvas_id in (select id from pg_temp.canvio_expired_content_ids);
    get diagnostics affected = row_count;
    deleted_counts := deleted_counts || jsonb_build_object('table_cells', affected);
  end if;

  -- Physically remove every row owned by an expired canvas/page, even when an
  -- old app version did not mark each child row as deleted.
  foreach sync_table in array array[
    'pdf_highlights',
    'pdf_ink_layers',
    'pdf_page_elements',
    'text_elements',
    'sticky_notes',
    'shapes',
    'image_elements',
    'pdf_elements',
    'todo_lists',
    'table_elements',
    'audio_elements',
    'youtube_elements',
    'drawings',
    'symbol_elements',
    'connectors',
    'element_groups'
  ] loop
    if to_regclass('public.' || sync_table) is not null
       and exists (
         select 1
         from information_schema.columns
         where table_schema = 'public'
           and table_name = sync_table
           and column_name = 'canvas_id'
       ) then
      execute format(
        'delete from public.%I where canvas_id in (select id from pg_temp.canvio_expired_content_ids)',
        sync_table
      );
      get diagnostics affected = row_count;
      deleted_counts := deleted_counts || jsonb_build_object(
        sync_table,
        coalesce((deleted_counts ->> sync_table)::bigint, 0) + affected
      );
    end if;
  end loop;

  -- Purge old page rows after their page content has been removed.
  if to_regclass('public.canvas_pages') is not null then
    delete from public.canvas_pages
    where canvas_id in (select id from pg_temp.canvio_expired_canvas_ids)
       or (is_deleted is true and updated_at < cutoff);
    get diagnostics affected = row_count;
    deleted_counts := deleted_counts || jsonb_build_object('canvas_pages', affected);
  end if;

  -- Purge standalone tombstones. Child tables are deliberately ordered before
  -- parents so this also works with restrictive foreign keys.
  foreach sync_table in array array[
    'todo_tasks',
    'table_cells',
    'pdf_highlights',
    'pdf_ink_layers',
    'pdf_page_elements',
    'text_elements',
    'sticky_notes',
    'shapes',
    'image_elements',
    'pdf_elements',
    'todo_lists',
    'table_elements',
    'audio_elements',
    'youtube_elements',
    'drawings',
    'symbol_elements',
    'connectors',
    'element_groups',
    'pdf_documents'
  ] loop
    if to_regclass('public.' || sync_table) is not null
       and exists (
         select 1
         from information_schema.columns
         where table_schema = 'public'
           and table_name = sync_table
           and column_name = 'is_deleted'
       )
       and exists (
         select 1
         from information_schema.columns
         where table_schema = 'public'
           and table_name = sync_table
           and column_name = 'updated_at'
       ) then
      execute format(
        'delete from public.%I where is_deleted is true and updated_at < $1',
        sync_table
      ) using cutoff;
      get diagnostics affected = row_count;
      deleted_counts := deleted_counts || jsonb_build_object(
        sync_table,
        coalesce((deleted_counts ->> sync_table)::bigint, 0) + affected
      );
    end if;
  end loop;

  -- Canvases are last because they own pages and many element tables.
  delete from public.canvases
  where id in (select id from pg_temp.canvio_expired_canvas_ids);
  get diagnostics affected = row_count;
  deleted_counts := deleted_counts || jsonb_build_object('canvases', affected);

  return jsonb_build_object(
    'cutoff', cutoff,
    'retention_days', extract(epoch from retention_period) / 86400,
    'deleted', deleted_counts
  );
end;
$$;

comment on function public.purge_canvio_sync_tombstones(interval) is
  'Permanently removes Canvio sync tombstones after the retention window and deletes content related to expired canvases/pages.';

revoke all on function public.purge_canvio_sync_tombstones(interval)
  from public, anon, authenticated;

-- Partial indexes keep the daily cleanup inexpensive as the sync tables grow.
do $$
declare
  sync_table text;
begin
  foreach sync_table in array array[
    'canvases',
    'canvas_pages',
    'element_groups',
    'text_elements',
    'sticky_notes',
    'shapes',
    'image_elements',
    'pdf_elements',
    'pdf_documents',
    'pdf_page_elements',
    'pdf_highlights',
    'pdf_ink_layers',
    'todo_lists',
    'todo_tasks',
    'table_elements',
    'table_cells',
    'audio_elements',
    'youtube_elements',
    'drawings',
    'symbol_elements',
    'connectors'
  ] loop
    if to_regclass('public.' || sync_table) is not null
       and exists (
         select 1
         from information_schema.columns
         where table_schema = 'public'
           and table_name = sync_table
           and column_name = 'is_deleted'
       )
       and exists (
         select 1
         from information_schema.columns
         where table_schema = 'public'
           and table_name = sync_table
           and column_name = 'updated_at'
       ) then
      execute format(
        'create index if not exists %I on public.%I(updated_at) where is_deleted is true',
        'idx_' || sync_table || '_deleted_updated',
        sync_table
      );
    end if;
  end loop;
end
$$;

-- Replace the named job if this migration is run again.
do $$
declare
  existing_job_id bigint;
begin
  select jobid into existing_job_id
  from cron.job
  where jobname = 'canvio-purge-sync-tombstones';

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;
end
$$;

select cron.schedule(
  'canvio-purge-sync-tombstones',
  '15 3 * * *',
  $cron$select public.purge_canvio_sync_tombstones(interval '30 days');$cron$
);

-- Clean up tombstones that are already beyond the retention window now. The
-- scheduled job handles every subsequent day.
select public.purge_canvio_sync_tombstones(interval '30 days');

commit;

