create table if not exists public.user_drawing_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  color_cycle_enabled boolean not null default false,
  color_cycle_colors text[] not null default array['#FF9500', '#007AFF', '#AF52DE']::text[],
  strokes_per_color integer not null default 3
    check (strokes_per_color between 1 and 50),
  color_cycle_mode text not null default 'byStroke'
    check (color_cycle_mode in ('byStroke', 'continuous')),
  continuous_color_speed text not null default 'medium'
    check (continuous_color_speed in ('slow', 'medium', 'fast')),
  updated_at timestamptz not null default now(),
  constraint user_drawing_settings_color_count
    check (cardinality(color_cycle_colors) between 1 and 5)
);

-- Safe when upgrading a project that already ran an earlier version of this file.
alter table public.user_drawing_settings
  add column if not exists color_cycle_mode text not null default 'byStroke';
alter table public.user_drawing_settings
  add column if not exists continuous_color_speed text not null default 'medium';

alter table public.user_drawing_settings
  drop constraint if exists user_drawing_settings_color_cycle_mode_check;
alter table public.user_drawing_settings
  add constraint user_drawing_settings_color_cycle_mode_check
    check (color_cycle_mode in ('byStroke', 'continuous'));

alter table public.user_drawing_settings
  drop constraint if exists user_drawing_settings_continuous_color_speed_check;
alter table public.user_drawing_settings
  add constraint user_drawing_settings_continuous_color_speed_check
    check (continuous_color_speed in ('slow', 'medium', 'fast'));

alter table public.user_drawing_settings enable row level security;

drop policy if exists "Users can read own drawing settings"
  on public.user_drawing_settings;
create policy "Users can read own drawing settings"
  on public.user_drawing_settings for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own drawing settings"
  on public.user_drawing_settings;
create policy "Users can insert own drawing settings"
  on public.user_drawing_settings for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own drawing settings"
  on public.user_drawing_settings;
create policy "Users can update own drawing settings"
  on public.user_drawing_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
