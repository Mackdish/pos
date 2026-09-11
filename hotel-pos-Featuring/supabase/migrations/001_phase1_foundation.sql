create extension if not exists pgcrypto;

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text,
  slug text not null unique,
  email text,
  phone text,
  address text,
  city text,
  county text,
  country text not null default 'Kenya',
  kra_pin text,
  vat_registered boolean not null default false,
  currency text not null default 'KES',
  timezone text not null default 'Africa/Nairobi',
  logo_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  code text not null,
  phone text,
  email text,
  address text,
  city text,
  county text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text,
  last_name text,
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  employee_number text,
  job_title text,
  status text not null default 'active' check (status in ('active','invited','suspended','terminated')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create unique index memberships_employee_number_uq
  on public.memberships (organization_id, employee_number)
  where employee_number is not null;

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text,
  created_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  code text not null,
  description text,
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table public.membership_roles (
  membership_id uuid not null references public.memberships(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (membership_id, role_id)
);

create table public.settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  key text not null,
  value jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index settings_scope_key_uq
  on public.settings (organization_id, coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid), key);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid references public.organizations(id) on delete set null,
  branch_id uuid references public.branches(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  old_data jsonb,
  new_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index branches_org_idx on public.branches(organization_id);
create index memberships_org_idx on public.memberships(organization_id);
create index memberships_user_idx on public.memberships(user_id);
create index memberships_branch_idx on public.memberships(branch_id);
create index roles_org_idx on public.roles(organization_id);
create index membership_roles_role_idx on public.membership_roles(role_id);
create index settings_org_idx on public.settings(organization_id);
create index settings_branch_idx on public.settings(branch_id);
create index audit_logs_org_created_idx on public.audit_logs(organization_id, created_at desc);
create index audit_logs_actor_idx on public.audit_logs(actor_user_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger organizations_updated_at before update on public.organizations for each row execute function public.set_updated_at();
create trigger branches_updated_at before update on public.branches for each row execute function public.set_updated_at();
create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger memberships_updated_at before update on public.memberships for each row execute function public.set_updated_at();
create trigger roles_updated_at before update on public.roles for each row execute function public.set_updated_at();
create trigger settings_updated_at before update on public.settings for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, first_name, last_name, phone)
  values (
    new.id,
    nullif(new.raw_user_meta_data->>'first_name', ''),
    nullif(new.raw_user_meta_data->>'last_name', ''),
    nullif(new.raw_user_meta_data->>'phone', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.current_user_id()
returns uuid
language sql
stable
as $$ select auth.uid(); $$;

create or replace function public.is_org_member(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.memberships m
    where m.organization_id = p_org_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;

create or replace function public.has_permission(p_org_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.memberships m
    join public.membership_roles mr on mr.membership_id = m.id
    join public.roles r on r.id = mr.role_id
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions p on p.id = rp.permission_id
    where m.organization_id = p_org_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and r.is_active = true
      and p.code = p_permission
  );
$$;

insert into public.permissions (code, description) values
('dashboard.view','View dashboard'),
('orders.create','Create orders'),
('orders.view','View orders'),
('orders.update','Update orders'),
('orders.cancel','Cancel orders'),
('payments.create','Record payments'),
('payments.verify','Verify payments'),
('payments.refund','Process refunds'),
('products.view','View products'),
('products.create','Create products'),
('products.update','Update products'),
('products.delete','Delete products'),
('inventory.view','View inventory'),
('inventory.receive','Receive stock'),
('inventory.adjust','Adjust stock'),
('inventory.transfer','Transfer stock'),
('customers.view','View customers'),
('customers.create','Create customers'),
('customers.update','Update customers'),
('reports.view','View reports'),
('reports.export','Export reports'),
('expenses.view','View expenses'),
('expenses.create','Create expenses'),
('expenses.approve','Approve expenses'),
('employees.view','View employees'),
('employees.create','Create employees'),
('employees.update','Update employees'),
('employees.disable','Disable employees'),
('employees.manage','Manage employee memberships'),
('settings.view','View settings'),
('settings.update','Update settings'),
('discounts.create','Create discounts'),
('discounts.approve','Approve discounts'),
('shifts.open','Open shifts'),
('shifts.close','Close shifts'),
('shifts.reconcile','Reconcile shifts'),
('audit.view','View audit logs'),
('rooms.view','View rooms'),
('rooms.manage','Manage rooms'),
('reservations.view','View reservations'),
('reservations.manage','Manage reservations'),
('folios.view','View folios'),
('folios.manage','Manage folios'),
('organization.view','View organization'),
('organization.manage','Manage organization'),
('branches.view','View branches'),
('branches.manage','Manage branches'),
('roles.view','View roles'),
('roles.manage','Manage roles')
on conflict (code) do nothing;

alter table public.organizations enable row level security;
alter table public.branches enable row level security;
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.permissions enable row level security;
alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.membership_roles enable row level security;
alter table public.settings enable row level security;
alter table public.audit_logs enable row level security;

create policy organizations_select on public.organizations for select to authenticated using (public.is_org_member(id));
create policy organizations_update on public.organizations for update to authenticated using (public.has_permission(id,'organization.manage')) with check (public.has_permission(id,'organization.manage'));

create policy branches_select on public.branches for select to authenticated using (public.is_org_member(organization_id));
create policy branches_insert on public.branches for insert to authenticated with check (public.has_permission(organization_id,'branches.manage'));
create policy branches_update on public.branches for update to authenticated using (public.has_permission(organization_id,'branches.manage')) with check (public.has_permission(organization_id,'branches.manage'));
create policy branches_delete on public.branches for delete to authenticated using (public.has_permission(organization_id,'branches.manage'));

create policy profiles_select on public.profiles for select to authenticated using (
  id = auth.uid() or exists (select 1 from public.memberships m where m.user_id = profiles.id and public.is_org_member(m.organization_id))
);
create policy profiles_update_self on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy memberships_select on public.memberships for select to authenticated using (public.is_org_member(organization_id));
create policy memberships_insert on public.memberships for insert to authenticated with check (public.has_permission(organization_id,'employees.manage'));
create policy memberships_update on public.memberships for update to authenticated using (public.has_permission(organization_id,'employees.manage')) with check (public.has_permission(organization_id,'employees.manage'));
create policy memberships_delete on public.memberships for delete to authenticated using (public.has_permission(organization_id,'employees.manage'));

create policy permissions_select on public.permissions for select to authenticated using (true);

create policy roles_select on public.roles for select to authenticated using (public.is_org_member(organization_id));
create policy roles_insert on public.roles for insert to authenticated with check (public.has_permission(organization_id,'roles.manage'));
create policy roles_update on public.roles for update to authenticated using (public.has_permission(organization_id,'roles.manage')) with check (public.has_permission(organization_id,'roles.manage'));
create policy roles_delete on public.roles for delete to authenticated using (public.has_permission(organization_id,'roles.manage'));

create policy role_permissions_select on public.role_permissions for select to authenticated using (
  exists (select 1 from public.roles r where r.id = role_permissions.role_id and public.is_org_member(r.organization_id))
);
create policy role_permissions_manage on public.role_permissions for all to authenticated using (
  exists (select 1 from public.roles r where r.id = role_permissions.role_id and public.has_permission(r.organization_id,'roles.manage'))
) with check (
  exists (select 1 from public.roles r where r.id = role_permissions.role_id and public.has_permission(r.organization_id,'roles.manage'))
);

create policy membership_roles_select on public.membership_roles for select to authenticated using (
  exists (select 1 from public.memberships m where m.id = membership_roles.membership_id and public.is_org_member(m.organization_id))
);
create policy membership_roles_manage on public.membership_roles for all to authenticated using (
  exists (select 1 from public.memberships m where m.id = membership_roles.membership_id and public.has_permission(m.organization_id,'roles.manage'))
) with check (
  exists (select 1 from public.memberships m where m.id = membership_roles.membership_id and public.has_permission(m.organization_id,'roles.manage'))
);

create policy settings_select on public.settings for select to authenticated using (public.has_permission(organization_id,'settings.view'));
create policy settings_insert on public.settings for insert to authenticated with check (public.has_permission(organization_id,'settings.update'));
create policy settings_update on public.settings for update to authenticated using (public.has_permission(organization_id,'settings.update')) with check (public.has_permission(organization_id,'settings.update'));
create policy settings_delete on public.settings for delete to authenticated using (public.has_permission(organization_id,'settings.update'));

create policy audit_logs_select on public.audit_logs for select to authenticated using (public.has_permission(organization_id,'audit.view'));

revoke all on public.audit_logs from anon, authenticated;
grant select on public.audit_logs to authenticated;
