-- Platform-level Super Admin support.
-- The initial bootstrap email is promoted automatically when the Auth user exists.
-- Passwords are never stored in the application database; Supabase Auth remains authoritative.

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'super_admin' check (role = 'super_admin'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;

create or replace function public.is_super_admin(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_admins
    where user_id = coalesce(p_user_id, auth.uid())
      and role = 'super_admin'
      and is_active = true
  );
$$;

revoke all on function public.is_super_admin(uuid) from public;
grant execute on function public.is_super_admin(uuid) to authenticated;

create policy platform_admins_self_select
on public.platform_admins
for select to authenticated
using (user_id = auth.uid());

create or replace function public.bootstrap_initial_super_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(coalesce(new.email, '')) = 'macknonvulimu@gmail.com' then
    insert into public.platform_admins (user_id, role, is_active)
    values (new.id, 'super_admin', true)
    on conflict (user_id) do update
      set role = 'super_admin', is_active = true, updated_at = now();
  end if;
  return new;
end;
$$;

revoke all on function public.bootstrap_initial_super_admin() from public;

create trigger on_initial_super_admin_created
after insert on auth.users
for each row execute function public.bootstrap_initial_super_admin();

-- If the requested Auth account already exists, promote it immediately.
insert into public.platform_admins (user_id, role, is_active)
select id, 'super_admin', true
from auth.users
where lower(email) = 'macknonvulimu@gmail.com'
on conflict (user_id) do update
  set role = 'super_admin', is_active = true, updated_at = now();

-- Super Admin can see and administer all tenant organizations.
create policy organizations_super_admin_select
on public.organizations
for select to authenticated
using (public.is_super_admin());

create policy organizations_super_admin_update
on public.organizations
for update to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

create policy organizations_super_admin_insert
on public.organizations
for insert to authenticated
with check (public.is_super_admin());

create policy organizations_super_admin_delete
on public.organizations
for delete to authenticated
using (public.is_super_admin());

create policy branches_super_admin_select
on public.branches
for select to authenticated
using (public.is_super_admin());

create policy branches_super_admin_update
on public.branches
for update to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

create policy branches_super_admin_insert
on public.branches
for insert to authenticated
with check (public.is_super_admin());

create policy branches_super_admin_delete
on public.branches
for delete to authenticated
using (public.is_super_admin());

create policy memberships_super_admin_select
on public.memberships
for select to authenticated
using (public.is_super_admin());

create policy memberships_super_admin_update
on public.memberships
for update to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

create policy memberships_super_admin_insert
on public.memberships
for insert to authenticated
with check (public.is_super_admin());

create policy memberships_super_admin_delete
on public.memberships
for delete to authenticated
using (public.is_super_admin());

create policy profiles_super_admin_select
on public.profiles
for select to authenticated
using (public.is_super_admin());

create policy roles_super_admin_all
on public.roles
for all to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

create policy role_permissions_super_admin_all
on public.role_permissions
for all to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

create policy membership_roles_super_admin_all
on public.membership_roles
for all to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

create policy settings_super_admin_all
on public.settings
for all to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

create policy audit_logs_super_admin_select
on public.audit_logs
for select to authenticated
using (public.is_super_admin());

create index if not exists platform_admins_active_idx
on public.platform_admins(is_active, role);
