-- ============================================================
-- ploty 공용함(회사 공용 재료함·기획함) 준비
-- Supabase 대시보드 → SQL Editor → 붙여넣고 Run 하면 됩니다.
-- 여러 번 실행해도 안전합니다.
-- ============================================================

-- 1) 멤버 명단: 여기에 등록된 계정에만 공용함이 보입니다
create table if not exists public.ploty_share_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_admin boolean not null default false,
  added_by uuid,
  created_at timestamptz not null default now()
);
alter table public.ploty_share_members enable row level security;

drop policy if exists "read own membership" on public.ploty_share_members;
create policy "read own membership" on public.ploty_share_members
  for select using (auth.uid() = user_id);

-- 2) 공용함 데이터 (재료·기획안·삭제 기록을 한 줄에 저장)
create table if not exists public.ploty_shared (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{"materials":[],"projects":[],"deleted":{}}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.ploty_shared enable row level security;

drop policy if exists "members read shared" on public.ploty_shared;
create policy "members read shared" on public.ploty_shared
  for select using (exists (select 1 from public.ploty_share_members m where m.user_id = auth.uid()));

drop policy if exists "members insert shared" on public.ploty_shared;
create policy "members insert shared" on public.ploty_shared
  for insert with check (exists (select 1 from public.ploty_share_members m where m.user_id = auth.uid()));

drop policy if exists "members update shared" on public.ploty_shared;
create policy "members update shared" on public.ploty_shared
  for update using (exists (select 1 from public.ploty_share_members m where m.user_id = auth.uid()))
  with check (exists (select 1 from public.ploty_share_members m where m.user_id = auth.uid()));

insert into public.ploty_shared (id) values (1) on conflict do nothing;

-- 3) 관리자용 함수: 아이디로 멤버 추가·빼기, 명단 보기
create or replace function public.ploty_add_member(member_id text)
returns text
language plpgsql security definer set search_path = public
as $$
declare tgt uuid;
begin
  if not exists (select 1 from ploty_share_members where user_id = auth.uid() and is_admin) then
    return '관리자만 멤버를 추가할 수 있어요.';
  end if;
  select id into tgt from auth.users where email = lower(trim(member_id)) || '@ploty.warmbread.app';
  if tgt is null then
    return '그 아이디로 가입한 계정을 찾지 못했어요.';
  end if;
  insert into ploty_share_members (user_id, added_by) values (tgt, auth.uid())
    on conflict (user_id) do nothing;
  return 'ok';
end $$;

create or replace function public.ploty_remove_member(member_id text)
returns text
language plpgsql security definer set search_path = public
as $$
declare tgt uuid;
begin
  if not exists (select 1 from ploty_share_members where user_id = auth.uid() and is_admin) then
    return '관리자만 멤버를 뺄 수 있어요.';
  end if;
  select id into tgt from auth.users where email = lower(trim(member_id)) || '@ploty.warmbread.app';
  if tgt is null then
    return '그 아이디로 가입한 계정을 찾지 못했어요.';
  end if;
  if tgt = auth.uid() then
    return '자기 자신(관리자)은 뺄 수 없어요.';
  end if;
  delete from ploty_share_members where user_id = tgt and not is_admin;
  return 'ok';
end $$;

create or replace function public.ploty_list_members()
returns table(member_id text, admin boolean)
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (select 1 from ploty_share_members where user_id = auth.uid() and is_admin) then
    return;
  end if;
  return query
    select split_part(u.email, '@', 1)::text, m.is_admin
    from ploty_share_members m
    join auth.users u on u.id = m.user_id
    order by m.is_admin desc, m.created_at;
end $$;

revoke execute on function public.ploty_add_member(text) from public, anon;
revoke execute on function public.ploty_remove_member(text) from public, anon;
revoke execute on function public.ploty_list_members() from public, anon;
grant execute on function public.ploty_add_member(text) to authenticated;
grant execute on function public.ploty_remove_member(text) to authenticated;
grant execute on function public.ploty_list_members() to authenticated;

-- 4) 대표님(warmbreadcorp) 계정을 관리자로 등록
insert into public.ploty_share_members (user_id, is_admin)
select id, true from auth.users where email = 'warmbreadcorp@ploty.warmbread.app'
on conflict (user_id) do update set is_admin = true;
