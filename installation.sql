-- À exécuter une fois dans Supabase > SQL Editor.
create table if not exists public.missions (
 mission_key text primary key,
 status text not null default 'todo' check (status in ('todo','submitted','revision','validated')),
 work text not null default '',
 comment text not null default '',
 updated_at timestamptz not null default now(),
 constraint key_format check (mission_key ~ '^[a-z]+:[0-9]+$')
);
alter table public.missions enable row level security;
revoke all on public.missions from anon, authenticated;
grant select on public.missions to anon, authenticated;
drop policy if exists "Public read missions" on public.missions;
create policy "Public read missions" on public.missions for select to anon,authenticated using (true);

create or replace function public.submit_mission(p_key text,p_work text)
returns void language plpgsql security definer set search_path = '' as $$
declare n integer; b text; i integer; previous_status text;
begin
 if p_key !~ '^[a-z]+:[0-9]+$' or length(p_work)>12000 or length(trim(p_work))=0 then raise exception 'Mission ou texte invalide'; end if;
 b:=split_part(p_key,':',1);i:=split_part(p_key,':',2)::integer;
 -- Les clés possibles sont strictement bornées à la liste des missions.
 n:=case b when 'dates' then 6 when 'transport' then 6 when 'camp' then 6 when 'meals' then 6 when 'activities' then 6 when 'budget' then 6 when 'families' then 6 when 'final' then 3 when 'choco' then 8 when 'soupe' then 8 when 'fruits' then 8 else 0 end;
 if i<0 or i>=n then raise exception 'Mission inconnue'; end if;
 if i>0 then
  select status into previous_status from public.missions where mission_key=b||':'||(i-1);
  if previous_status is distinct from 'validated' then raise exception 'Mission précédente non validée'; end if;
 end if;
 insert into public.missions(mission_key,status,work,comment) values(p_key,'submitted',p_work,'')
 on conflict(mission_key) do update set status='submitted',work=excluded.work,updated_at=now()
 where public.missions.status in ('todo','revision');
 if not found then raise exception 'Mission déjà envoyée ou validée'; end if;
end $$;
revoke all on function public.submit_mission(text,text) from public;
grant execute on function public.submit_mission(text,text) to anon,authenticated;

create or replace function public.review_mission(p_key text,p_action text,p_comment text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare current_status text;
begin
 if auth.uid() is null or (auth.jwt()->>'email') is distinct from 'fricot.arthur@gmail.com' then raise exception 'Accès enseignant uniquement'; end if;
 if p_action not in ('validated','revision') or length(p_comment)>12000 then raise exception 'Action invalide'; end if;
 select status into current_status from public.missions where mission_key=p_key for update;
 if current_status is null or current_status not in ('submitted','validated') then raise exception 'Mission non soumise'; end if;
 update public.missions set status=p_action,comment=p_comment,updated_at=now() where mission_key=p_key;
end $$;
revoke all on function public.review_mission(text,text,text) from public;
grant execute on function public.review_mission(text,text,text) to authenticated;
-- Facultatif : activer la table missions dans Database > Publications > supabase_realtime.
