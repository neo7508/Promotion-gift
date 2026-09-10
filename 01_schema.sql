-- ============================================================
--  판촉물 관리 시스템 — Supabase 초기 구축 SQL
--  광고영업팀 외 · 사용자 20명 내외 · 전사 공용 재고 1벌
--
--  실행 방법
--    Supabase 콘솔 → 왼쪽 메뉴 SQL Editor → New query
--    이 파일 전체를 붙여넣고 Run
--    (여러 번 실행해도 안전하도록 작성돼 있습니다)
--
--  주의: 프로젝트 생성 시 리전을 Northeast Asia (Seoul) 로 선택했는지
--        먼저 확인하세요. 생성 후에는 변경할 수 없습니다.
-- ============================================================


-- ============================================================
--  1. 계정 (profiles)
--     로그인 자체는 Supabase Auth(auth.users)가 담당합니다.
--     비밀번호는 여기에 저장되지 않습니다. 해시 값만 auth 스키마에
--     보관되며 관리자도 원본을 볼 수 없습니다.
--     이 테이블에는 이름 · 이메일 · 권한 · 승인상태만 둡니다.
-- ============================================================

create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null,
  email       text not null,
  role        text not null default 'member'  check (role   in ('member','admin')),
  status      text not null default 'pending' check (status in ('pending','approved','rejected','inactive')),
  created_at  timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references public.profiles(id)
);

comment on table  public.profiles       is '서비스 계정. 가입 시 이름/이메일만 수집';
comment on column public.profiles.status is 'pending=승인대기, approved=사용중, rejected=반려, inactive=퇴직·전배(이력 보존용)';

-- 가입하면 자동으로 pending 상태의 profile 생성
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, name, email)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'name'), ''), split_part(new.email,'@',1)),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================
--  2. 권한 판정 함수
--     RLS 정책 안에서 profiles를 직접 조회하면 정책이 자기 자신을
--     다시 호출하는 무한 재귀가 생깁니다. security definer 함수로
--     한 번 감싸서 그 문제를 피합니다.
-- ============================================================

create or replace function public.is_approved()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'approved'
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'approved' and role = 'admin'
  );
$$;


-- ============================================================
--  3. 품목 (items)
-- ============================================================

create table if not exists public.items (
  id          bigint generated always as identity primary key,
  name        text not null,
  unit_price  integer not null default 0,          -- 구매 단가(원)
  location    text,                                -- 보관 위치: 런던1, 탕비실 등
  batch       text,                                -- 구매 차수: '26년 7월 구매'
  image_path  text,                                -- Storage 파일 경로
  link        text,                                -- 구매처 참고 링크
  active      boolean not null default true,       -- false면 신청 화면에서 숨김
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles(id)
);

create index if not exists items_active_idx on public.items(active);


-- ============================================================
--  4. 입고 (stock_ins) — 구매해서 들어온 수량
-- ============================================================

create table if not exists public.stock_ins (
  id          bigint generated always as identity primary key,
  item_id     bigint not null references public.items(id) on delete cascade,
  qty         integer not null check (qty > 0),
  in_date     date not null default current_date,
  unit_price  integer,                             -- 이번 입고분 단가(선택)
  memo        text,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles(id)
);

create index if not exists stock_ins_item_idx on public.stock_ins(item_id);


-- ============================================================
--  5. 재고 보정 (stock_adjustments) — 실사 결과 반영
--     파손·분실·기록 누락을 구매 수량에 섞으면 "얼마 샀는지"가
--     왜곡됩니다. 별도로 쌓아서 추적 가능하게 둡니다.
-- ============================================================

create table if not exists public.stock_adjustments (
  id          bigint generated always as identity primary key,
  item_id     bigint not null references public.items(id) on delete cascade,
  delta       integer not null check (delta <> 0),  -- +3 / -2
  reason      text not null,                        -- 사유 필수
  adj_date    date not null default current_date,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles(id)
);

create index if not exists stock_adj_item_idx on public.stock_adjustments(item_id);


-- ============================================================
--  6. 사용 신청 (handouts / handout_lines)
--     한 건에 여러 품목이 들어가므로 머리(handouts)와
--     품목줄(handout_lines)로 나눕니다.
-- ============================================================

create table if not exists public.handouts (
  id           bigint generated always as identity primary key,
  handout_date date not null default current_date,
  user_id      uuid not null references public.profiles(id),
  handler_name text not null,          -- 등록 시점의 이름을 그대로 남김
  company      text not null,          -- 방문업체 · 대상
  memo         text,
  created_at   timestamptz not null default now()
);

create index if not exists handouts_date_idx on public.handouts(handout_date desc);
create index if not exists handouts_user_idx on public.handouts(user_id);

create table if not exists public.handout_lines (
  id         bigint generated always as identity primary key,
  handout_id bigint not null references public.handouts(id) on delete cascade,
  item_id    bigint not null references public.items(id),
  qty        integer not null check (qty > 0),
  unique (handout_id, item_id)
);

create index if not exists handout_lines_item_idx on public.handout_lines(item_id);


-- ============================================================
--  7. 재고 계산 뷰
--     재고 = 입고 + 보정 − 사용
--     앱은 items를 직접 읽지 않고 이 뷰를 읽습니다.
-- ============================================================

create or replace view public.item_stock
with (security_invoker = on) as
select
  i.id, i.name, i.unit_price, i.location, i.batch,
  i.image_path, i.link, i.active,
  coalesce(b.qty, 0)                                   as bought,      -- 누적 입고
  coalesce(a.qty, 0)                                   as adjusted,    -- 누적 보정
  coalesce(o.qty, 0)                                   as handed_out,  -- 누적 사용
  coalesce(b.qty, 0) + coalesce(a.qty, 0) - coalesce(o.qty, 0) as stock
from public.items i
left join (select item_id, sum(qty)   as qty from public.stock_ins          group by item_id) b on b.item_id = i.id
left join (select item_id, sum(delta) as qty from public.stock_adjustments  group by item_id) a on a.item_id = i.id
left join (select item_id, sum(qty)   as qty from public.handout_lines      group by item_id) o on o.item_id = i.id;


-- ============================================================
--  8. 재고 초과 방지
--     남은 수량보다 많이 신청하는 것을 데이터베이스가 막습니다.
--     화면에서 막는 것과 별개로 한 겹 더 둡니다.
-- ============================================================

create or replace function public.check_stock()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  remaining integer;
  item_name text;
begin
  select s.stock, s.name into remaining, item_name
  from public.item_stock s where s.id = new.item_id;

  if tg_op = 'UPDATE' then
    remaining := remaining + old.qty;   -- 기존 수량은 되돌려놓고 비교
  end if;

  if new.qty > remaining then
    raise exception '재고가 부족합니다. % 남은 수량: %개', item_name, remaining;
  end if;
  return new;
end;
$$;

drop trigger if exists handout_lines_stock_check on public.handout_lines;
create trigger handout_lines_stock_check
  before insert or update on public.handout_lines
  for each row execute function public.check_stock();


-- ============================================================
--  9. 접근 권한 (RLS)
--     여기가 승인제의 핵심입니다.
--     화면 코드가 아니라 데이터베이스가 막기 때문에,
--     브라우저를 조작해도 승인 대기 계정은 아무것도 볼 수 없습니다.
-- ============================================================

alter table public.profiles          enable row level security;
alter table public.items             enable row level security;
alter table public.stock_ins         enable row level security;
alter table public.stock_adjustments enable row level security;
alter table public.handouts          enable row level security;
alter table public.handout_lines     enable row level security;

-- ---- profiles ----
drop policy if exists "본인 프로필 조회"     on public.profiles;
drop policy if exists "승인자는 전체 조회"   on public.profiles;
drop policy if exists "본인 이름 수정"       on public.profiles;
drop policy if exists "관리자만 승인·권한변경" on public.profiles;

create policy "본인 프로필 조회" on public.profiles
  for select using (id = auth.uid());

create policy "승인자는 전체 조회" on public.profiles
  for select using (public.is_approved());

create policy "본인 이름 수정" on public.profiles
  for update using (id = auth.uid())
  with check (
    id = auth.uid()
    -- 본인이 자기 권한이나 승인상태를 바꾸는 것은 차단
    and role   = (select p.role   from public.profiles p where p.id = auth.uid())
    and status = (select p.status from public.profiles p where p.id = auth.uid())
  );

create policy "관리자만 승인·권한변경" on public.profiles
  for update using (public.is_admin()) with check (public.is_admin());

-- ---- items / stock_ins / stock_adjustments : 조회는 승인자, 변경은 관리자 ----
do $$
declare t text;
begin
  foreach t in array array['items','stock_ins','stock_adjustments'] loop
    execute format('drop policy if exists "승인자 조회" on public.%I', t);
    execute format('drop policy if exists "관리자 변경" on public.%I', t);
    execute format('create policy "승인자 조회" on public.%I for select using (public.is_approved())', t);
    execute format('create policy "관리자 변경" on public.%I for all using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

-- ---- handouts : 승인자는 전체 조회, 본인 것만 등록 ----
drop policy if exists "승인자 조회"       on public.handouts;
drop policy if exists "본인 명의로 등록"  on public.handouts;
drop policy if exists "본인 30분내 수정"  on public.handouts;
drop policy if exists "본인 30분내 삭제"  on public.handouts;

create policy "승인자 조회" on public.handouts
  for select using (public.is_approved());

create policy "본인 명의로 등록" on public.handouts
  for insert with check (public.is_approved() and user_id = auth.uid());

-- 등록 직후 30분 안에는 본인이 고칠 수 있고, 이후에는 관리자만
create policy "본인 30분내 수정" on public.handouts
  for update using (
    public.is_admin()
    or (user_id = auth.uid() and created_at > now() - interval '30 minutes')
  );

create policy "본인 30분내 삭제" on public.handouts
  for delete using (
    public.is_admin()
    or (user_id = auth.uid() and created_at > now() - interval '30 minutes')
  );

-- ---- handout_lines : 머리(handouts) 권한을 그대로 따라감 ----
drop policy if exists "승인자 조회"  on public.handout_lines;
drop policy if exists "본인 건 편집" on public.handout_lines;

create policy "승인자 조회" on public.handout_lines
  for select using (public.is_approved());

create policy "본인 건 편집" on public.handout_lines
  for all using (
    exists (
      select 1 from public.handouts h
      where h.id = handout_id
        and (public.is_admin()
             or (h.user_id = auth.uid() and h.created_at > now() - interval '30 minutes'))
    )
  )
  with check (
    exists (
      select 1 from public.handouts h
      where h.id = handout_id
        and (public.is_admin()
             or (h.user_id = auth.uid() and h.created_at > now() - interval '30 minutes'))
    )
  );


-- ============================================================
--  10. 제품 사진 저장소
-- ============================================================

insert into storage.buckets (id, name, public)
values ('item-photos', 'item-photos', true)
on conflict (id) do nothing;

drop policy if exists "사진 조회 허용"   on storage.objects;
drop policy if exists "관리자만 사진 등록" on storage.objects;

create policy "사진 조회 허용" on storage.objects
  for select using (bucket_id = 'item-photos');

create policy "관리자만 사진 등록" on storage.objects
  for all to authenticated
  using      (bucket_id = 'item-photos' and public.is_admin())
  with check (bucket_id = 'item-photos' and public.is_admin());


-- ============================================================
--  실행 후 할 일
-- ============================================================
--
--  (1) 가입 도메인 제한
--      Authentication → Sign In / Providers → Email
--      · Confirm email 켜기 (본인 메일 인증)
--      · Authentication → Settings 의 허용 도메인에
--        skbroadband.com 만 등록
--
--  (2) 본인 계정으로 회원가입한 뒤, 아래를 실행해 첫 관리자 지정
--      (이후로는 화면에서 승인·권한변경이 됩니다)
--
--      update public.profiles
--         set role = 'admin', status = 'approved', approved_at = now()
--       where email = '여기에@본인이메일.com';
--
--  (3) 관리자는 최소 2명 지정하세요.
--      승인해줄 사람이 자리를 비우면 신규 입사자가 며칠씩 들어오지 못합니다.
--
--  (4) 퇴직·전배자는 계정을 삭제하지 말고 status를 inactive로 바꾸세요.
--      삭제하면 그 사람이 남긴 배포 이력까지 함께 사라집니다.
--
--      update public.profiles set status = 'inactive' where email = '...';
--
-- ============================================================
