create or replace function public.create_organization_with_admin(
  p_name text,
  p_branch_name text,
  p_branch_code text,
  p_email text default null,
  p_phone text default null
)
returns table (organization_id uuid, branch_id uuid, membership_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_org public.organizations;
  v_branch public.branches;
  v_membership public.memberships;
  v_admin_role public.roles;
  v_manager_role public.roles;
  v_cashier_role public.roles;
  v_waiter_role public.roles;
  v_reception_role public.roles;
  v_permission record;
  v_slug text;
  v_code text;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if exists (select 1 from public.memberships where user_id = v_user_id and status in ('active','invited')) then
    raise exception 'You already belong to an organization';
  end if;
  if nullif(trim(p_name), '') is null then raise exception 'Organization name is required'; end if;
  if nullif(trim(p_branch_name), '') is null then raise exception 'Branch name is required'; end if;

  v_slug := regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g');
  v_slug := trim(both '-' from v_slug);
  if v_slug = '' then v_slug := 'organization'; end if;
  if exists (select 1 from public.organizations where slug = v_slug) then
    v_slug := v_slug || '-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  end if;

  v_code := upper(regexp_replace(coalesce(nullif(trim(p_branch_code), ''), 'MAIN'), '[^A-Z0-9]+', '', 'g'));
  if v_code = '' then v_code := 'MAIN'; end if;

  insert into public.organizations (name, slug, email, phone)
  values (trim(p_name), v_slug, nullif(trim(p_email), ''), nullif(trim(p_phone), ''))
  returning * into v_org;

  insert into public.branches (organization_id, name, code, email, phone)
  values (v_org.id, trim(p_branch_name), v_code, v_org.email, v_org.phone)
  returning * into v_branch;

  insert into public.roles (organization_id, name, code, description, is_system)
  values
    (v_org.id, 'Administrator', 'admin', 'Full access to organization operations', true),
    (v_org.id, 'Manager', 'manager', 'Operational management access', true),
    (v_org.id, 'Cashier', 'cashier', 'Sales and payment operations', true),
    (v_org.id, 'Waiter', 'waiter', 'Restaurant order operations', true),
    (v_org.id, 'Receptionist', 'receptionist', 'Hotel front desk operations', true)
  returning id into v_admin_role;

  select * into v_admin_role from public.roles where organization_id = v_org.id and code = 'admin';
  select * into v_manager_role from public.roles where organization_id = v_org.id and code = 'manager';
  select * into v_cashier_role from public.roles where organization_id = v_org.id and code = 'cashier';
  select * into v_waiter_role from public.roles where organization_id = v_org.id and code = 'waiter';
  select * into v_reception_role from public.roles where organization_id = v_org.id and code = 'receptionist';

  insert into public.role_permissions (role_id, permission_id)
  select v_admin_role.id, p.id from public.permissions p;

  insert into public.role_permissions (role_id, permission_id)
  select v_manager_role.id, p.id from public.permissions p
  where p.code not in ('organization.manage','branches.manage','roles.manage');

  insert into public.role_permissions (role_id, permission_id)
  select v_cashier_role.id, p.id from public.permissions p
  where p.code in ('dashboard.view','orders.create','orders.view','orders.update','payments.create','payments.verify','products.view','reports.view','shifts.open','shifts.close');

  insert into public.role_permissions (role_id, permission_id)
  select v_waiter_role.id, p.id from public.permissions p
  where p.code in ('dashboard.view','orders.create','orders.view','orders.update','products.view');

  insert into public.role_permissions (role_id, permission_id)
  select v_reception_role.id, p.id from public.permissions p
  where p.code in ('dashboard.view','orders.view','orders.create','payments.create','products.view','rooms.view','reservations.view','reservations.manage','folios.view','folios.manage');

  insert into public.memberships (organization_id, user_id, branch_id, job_title, status)
  values (v_org.id, v_user_id, v_branch.id, 'Administrator', 'active')
  returning * into v_membership;

  insert into public.membership_roles (membership_id, role_id)
  values (v_membership.id, v_admin_role.id);

  return query select v_org.id, v_branch.id, v_membership.id;
end;
$$;

revoke all on function public.create_organization_with_admin(text,text,text,text,text) from public;
grant execute on function public.create_organization_with_admin(text,text,text,text,text) to authenticated;
