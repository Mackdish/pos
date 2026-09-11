create or replace function public.provision_default_roles(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role_id uuid;
begin
  if not public.is_org_member(p_org_id) then
    raise exception 'Not authorized';
  end if;

  insert into public.roles (organization_id, name, code, description, is_system)
  values
    (p_org_id, 'Owner', 'Owner', 'Full organization access', true),
    (p_org_id, 'Manager', 'Manager', 'Operational management access', true),
    (p_org_id, 'Cashier', 'Cashier', 'POS and payment operations', true),
    (p_org_id, 'Waiter', 'Waiter', 'Restaurant order operations', true),
    (p_org_id, 'Receptionist', 'Receptionist', 'Front desk and hotel operations', true)
  on conflict (organization_id, code) do nothing;

  select id into v_role_id from public.roles where organization_id = p_org_id and code = 'Owner';
  insert into public.role_permissions(role_id, permission_id)
  select v_role_id, p.id from public.permissions p
  on conflict do nothing;
end;
$$;

create or replace function public.create_organization(
  p_name text,
  p_slug text,
  p_branch_name text default 'Main Branch',
  p_branch_code text default 'MAIN'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_org_id uuid;
  v_branch_id uuid;
  v_membership_id uuid;
  v_role_id uuid;
begin
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  if nullif(trim(p_name), '') is null or nullif(trim(p_slug), '') is null then
    raise exception 'Organization name and slug are required';
  end if;

  insert into public.organizations (name, slug)
  values (trim(p_name), lower(trim(p_slug)))
  returning id into v_org_id;

  insert into public.branches (organization_id, name, code)
  values (v_org_id, coalesce(nullif(trim(p_branch_name), ''), 'Main Branch'), upper(coalesce(nullif(trim(p_branch_code), ''), 'MAIN')))
  returning id into v_branch_id;

  insert into public.memberships (organization_id, user_id, branch_id, job_title, status)
  values (v_org_id, v_user, v_branch_id, 'Owner', 'active')
  returning id into v_membership_id;

  insert into public.roles (organization_id, name, code, description, is_system)
  values (v_org_id, 'Owner', 'Owner', 'Full organization access', true)
  returning id into v_role_id;

  insert into public.role_permissions (role_id, permission_id)
  select v_role_id, id from public.permissions
  on conflict do nothing;

  insert into public.roles (organization_id, name, code, description, is_system)
  values
    (v_org_id, 'Manager', 'Manager', 'Operational management access', true),
    (v_org_id, 'Cashier', 'Cashier', 'POS and payment operations', true),
    (v_org_id, 'Waiter', 'Waiter', 'Restaurant order operations', true),
    (v_org_id, 'Receptionist', 'Receptionist', 'Front desk and hotel operations', true)
  on conflict (organization_id, code) do nothing;

  insert into public.membership_roles (membership_id, role_id)
  values (v_membership_id, v_role_id);

  return v_org_id;
end;
$$;

revoke execute on function public.create_organization(text,text,text,text) from public;
grant execute on function public.create_organization(text,text,text,text) to authenticated;

create or replace function public.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_branch uuid;
  v_id text;
begin
  if tg_op = 'DELETE' then
    v_org := case when to_jsonb(old) ? 'organization_id' then (to_jsonb(old)->>'organization_id')::uuid else null end;
    v_branch := case when to_jsonb(old) ? 'branch_id' and (to_jsonb(old)->>'branch_id') is not null then (to_jsonb(old)->>'branch_id')::uuid else null end;
    v_id := coalesce(to_jsonb(old)->>'id', to_jsonb(old)->>'order_number');
  else
    v_org := case when to_jsonb(new) ? 'organization_id' then (to_jsonb(new)->>'organization_id')::uuid else null end;
    v_branch := case when to_jsonb(new) ? 'branch_id' and (to_jsonb(new)->>'branch_id') is not null then (to_jsonb(new)->>'branch_id')::uuid else null end;
    v_id := coalesce(to_jsonb(new)->>'id', to_jsonb(new)->>'order_number');
  end if;

  insert into public.audit_logs (organization_id, branch_id, actor_user_id, action, entity_type, entity_id, old_data, new_data)
  values (
    v_org, v_branch, auth.uid(), lower(tg_op), tg_table_name, v_id,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger audit_orders_changes
after insert or update or delete on public.orders
for each row execute function public.audit_row_change();

create trigger audit_payments_changes
after insert or update or delete on public.payments
for each row execute function public.audit_row_change();
