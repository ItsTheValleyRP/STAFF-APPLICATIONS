-- THE VALLEY | STAFF PORTAL SECURITY HARDENING
-- Run only AFTER the original application portal tables exist.
-- Additive and non-destructive: does not delete applications, roles, or audit history.
-- Uses the existing Super Owner UUID from the original portal setup.

begin;

-- ---------------------------------------------------------------------------
-- 1) Trusted permission checks. These run on the database, not in the browser.
-- ---------------------------------------------------------------------------

create or replace function public.valley_is_super_owner()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() = '193a2e89-2bbb-496d-851d-1bb50aeb0b62'::uuid
$$;

create or replace function public.valley_has_role(p_scope text, p_role text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.valley_is_super_owner()
    or exists (
      select 1
      from public.valley_application_roles r
      where r.user_id = auth.uid()
        and r.scope = p_scope
        and r.role_key = p_role
    )
$$;

create or replace function public.valley_can_review(p_department text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when auth.uid() is null then false
    when public.valley_is_super_owner() then true
    when p_department = 'staff' then (
      public.valley_has_role('staff','staff_owner')
      or public.valley_has_role('staff','director')
      or public.valley_has_role('staff','assistant_director')
      or public.valley_has_role('staff','management')
    )
    when p_department in ('lspd','ems','doj') then (
      public.valley_has_role(p_department,'department_head')
      or public.valley_has_role(p_department,'command_team')
      or public.valley_has_role(p_department,'application_reviewer')
    )
    else false
  end
$$;

-- ---------------------------------------------------------------------------
-- 2) Enable RLS and explicitly restrict direct table access.
--    Authenticated users may SELECT only what the policies below allow.
--    Browser clients cannot INSERT, UPDATE, or DELETE application records.
-- ---------------------------------------------------------------------------

alter table public.valley_application_roles enable row level security;
alter table public.valley_application_forms enable row level security;
alter table public.valley_applications enable row level security;
alter table public.valley_application_audit enable row level security;

drop policy if exists valley_roles_read_self on public.valley_application_roles;
create policy valley_roles_read_self
on public.valley_application_roles
for select to authenticated
using (user_id = auth.uid() or public.valley_is_super_owner());

drop policy if exists valley_forms_read_signed_in on public.valley_application_forms;
create policy valley_forms_read_signed_in
on public.valley_application_forms
for select to authenticated
using (true);

drop policy if exists valley_apps_read_own_or_reviewable on public.valley_applications;
create policy valley_apps_read_own_or_reviewable
on public.valley_applications
for select to authenticated
using (applicant_id = auth.uid() or public.valley_can_review(department));

drop policy if exists valley_audit_read_super_owner on public.valley_application_audit;
create policy valley_audit_read_super_owner
on public.valley_application_audit
for select to authenticated
using (public.valley_is_super_owner());

revoke all on table public.valley_application_roles from anon, authenticated;
revoke all on table public.valley_application_forms from anon, authenticated;
revoke all on table public.valley_applications from anon, authenticated;
revoke all on table public.valley_application_audit from anon, authenticated;

grant select on table public.valley_application_roles to authenticated;
grant select on table public.valley_application_forms to authenticated;
grant select on table public.valley_applications to authenticated;
grant select on table public.valley_application_audit to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Safe RPC endpoints used by the new Staff website.
--    SECURITY DEFINER lets these functions perform controlled writes while
--    validating the signed-in user and permissions on every request.
-- ---------------------------------------------------------------------------

create or replace function public.valley_portal_get_my_roles()
returns table(scope text, role_key text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select 'system'::text, 'super_owner'::text
  where auth.uid() is not null and public.valley_is_super_owner()
  union all
  select r.scope, r.role_key
  from public.valley_application_roles r
  where r.user_id = auth.uid()
$$;

create or replace function public.valley_portal_submit_application(
  p_department text,
  p_answers jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Please sign in first.';
  end if;

  if p_department not in ('staff','lspd','ems','doj') then
    raise exception 'Invalid application department.';
  end if;

  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Application answers must be a valid object.';
  end if;

  if not exists (
    select 1 from public.valley_application_forms f
    where f.department = p_department and f.is_open = true
  ) then
    raise exception 'Applications for this department are currently closed.';
  end if;

  if exists (
    select 1 from public.valley_applications a
    where a.applicant_id = auth.uid()
      and a.department = p_department
      and a.status in ('pending','under_review','changes_requested')
  ) then
    raise exception 'You already have an active application for this department.';
  end if;

  insert into public.valley_applications(applicant_id, department, answers)
  values(auth.uid(), p_department, p_answers)
  returning id into v_id;

  insert into public.valley_application_audit(
    actor_id, target_user_id, application_id, action, details
  )
  values(
    auth.uid(), auth.uid(), v_id, 'application_submitted',
    jsonb_build_object('department', p_department)
  );

  return v_id;
end
$$;

create or replace function public.valley_portal_review_application(
  p_application_id uuid,
  p_status text,
  p_notes text default ''
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_app public.valley_applications%rowtype;
  v_notes text := coalesce(p_notes, '');
begin
  if auth.uid() is null then
    raise exception 'Please sign in first.';
  end if;

  if p_status not in ('under_review','approved','denied','changes_requested') then
    raise exception 'Invalid review status.';
  end if;

  if length(v_notes) > 3000 then
    raise exception 'Reviewer notes cannot exceed 3000 characters.';
  end if;

  select * into v_app
  from public.valley_applications
  where id = p_application_id
  for update;

  if not found then
    raise exception 'Application not found.';
  end if;

  if not public.valley_can_review(v_app.department) then
    raise exception 'You do not have permission to review this application.';
  end if;

  update public.valley_applications
  set status = p_status,
      reviewer_id = auth.uid(),
      review_notes = v_notes,
      updated_at = now()
  where id = p_application_id;

  insert into public.valley_application_audit(
    actor_id, target_user_id, application_id, action, details
  )
  values(
    auth.uid(), v_app.applicant_id, p_application_id, 'application_reviewed',
    jsonb_build_object('department', v_app.department, 'status', p_status, 'notes', v_notes)
  );

  return true;
end
$$;

-- ---------------------------------------------------------------------------
-- 4) Remove default PUBLIC/anon execution and grant only authenticated users.
-- ---------------------------------------------------------------------------

revoke all on function public.valley_is_super_owner() from public, anon;
revoke all on function public.valley_has_role(text,text) from public, anon;
revoke all on function public.valley_can_review(text) from public, anon;
revoke all on function public.valley_portal_get_my_roles() from public, anon;
revoke all on function public.valley_portal_submit_application(text,jsonb) from public, anon;
revoke all on function public.valley_portal_review_application(uuid,text,text) from public, anon;

grant execute on function public.valley_is_super_owner() to authenticated;
grant execute on function public.valley_has_role(text,text) to authenticated;
grant execute on function public.valley_can_review(text) to authenticated;
grant execute on function public.valley_portal_get_my_roles() to authenticated;
grant execute on function public.valley_portal_submit_application(text,jsonb) to authenticated;
grant execute on function public.valley_portal_review_application(uuid,text,text) to authenticated;

commit;

-- After running: test with a normal applicant account and a Staff reviewer account.
-- Never put a Supabase service_role/secret key in index.html or any public repository.
