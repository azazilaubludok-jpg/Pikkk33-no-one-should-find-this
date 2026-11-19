-- «Стенка»: схема базы для Supabase.
-- Вставь целиком в Supabase → SQL Editor → New query → Run.

create table if not exists public.posts (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  nick        text not null default '' check (char_length(nick) <= 32),
  body        text not null check (char_length(btrim(body)) between 1 and 500)
);

create index if not exists posts_created_at_idx on public.posts (created_at desc);

-- Доступ: читать и писать могут все, менять и удалять — никто (кроме тебя из панели Supabase).
alter table public.posts enable row level security;

-- Новые проекты Supabase не дают гостям доступ к таблицам сами — выдаём явно.
grant select, insert on public.posts to anon, authenticated;
grant usage on sequence public.posts_id_seq to anon, authenticated;

drop policy if exists "все читают" on public.posts;
create policy "все читают" on public.posts
  for select to anon, authenticated using (true);

drop policy if exists "все пишут" on public.posts;
create policy "все пишут" on public.posts
  for insert to anon, authenticated with check (true);

-- Защита от флуда: не больше 30 постов в минуту на всю стену.
create or replace function public.posts_flood_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.posts where created_at > now() - interval '1 minute') >= 30 then
    raise exception 'Слишком много постов, подожди минуту';
  end if;
  new.created_at := now();   -- время ставит сервер, а не браузер
  new.body := btrim(new.body);
  new.nick := btrim(new.nick);
  return new;
end $$;

drop trigger if exists posts_flood_guard on public.posts;
create trigger posts_flood_guard before insert on public.posts
  for each row execute function public.posts_flood_guard();

-- Новые посты появляются у всех сразу (realtime).
do $$ begin
  alter publication supabase_realtime add table public.posts;
exception when duplicate_object then null; end $$;
