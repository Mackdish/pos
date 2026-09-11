create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  sku text,
  unit text not null default 'unit',
  reorder_level numeric(14,3) not null default 0 check (reorder_level >= 0),
  cost_price numeric(14,2) not null default 0 check (cost_price >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, sku)
);

create table public.stock_levels (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id) on delete cascade,
  quantity numeric(14,3) not null default 0,
  updated_at timestamptz not null default now(),
  unique (branch_id, inventory_item_id)
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  movement_type text not null check (movement_type in ('opening','receive','issue','adjustment','transfer_in','transfer_out','sale')),
  quantity numeric(14,3) not null check (quantity <> 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  reference text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index inventory_items_org_idx on public.inventory_items(organization_id, is_active);
create index stock_levels_branch_idx on public.stock_levels(branch_id);
create index stock_movements_branch_created_idx on public.stock_movements(branch_id, created_at desc);
create index stock_movements_item_idx on public.stock_movements(inventory_item_id, created_at desc);

create trigger inventory_items_updated_at before update on public.inventory_items for each row execute function public.set_updated_at();
create trigger stock_levels_updated_at before update on public.stock_levels for each row execute function public.set_updated_at();

alter table public.inventory_items enable row level security;
alter table public.stock_levels enable row level security;
alter table public.stock_movements enable row level security;

create policy inventory_items_select on public.inventory_items for select to authenticated using (public.is_org_member(organization_id));
create policy inventory_items_insert on public.inventory_items for insert to authenticated with check (public.has_permission(organization_id,'inventory.receive'));
create policy inventory_items_update on public.inventory_items for update to authenticated using (public.has_permission(organization_id,'inventory.adjust')) with check (public.has_permission(organization_id,'inventory.adjust'));

create policy stock_levels_select on public.stock_levels for select to authenticated using (public.is_org_member(organization_id));
create policy stock_levels_manage on public.stock_levels for all to authenticated using (public.has_permission(organization_id,'inventory.adjust') or public.has_permission(organization_id,'inventory.receive')) with check (public.has_permission(organization_id,'inventory.adjust') or public.has_permission(organization_id,'inventory.receive'));

create policy stock_movements_select on public.stock_movements for select to authenticated using (public.is_org_member(organization_id));
create policy stock_movements_insert on public.stock_movements for insert to authenticated with check (public.has_permission(organization_id,'inventory.adjust') or public.has_permission(organization_id,'inventory.receive'));

create or replace function public.record_stock_movement(
  p_branch_id uuid,
  p_inventory_item_id uuid,
  p_movement_type text,
  p_quantity numeric,
  p_unit_cost numeric default 0,
  p_reference text default null,
  p_notes text default null
)
returns public.stock_levels
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_level public.stock_levels;
  v_permission text;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_movement_type not in ('opening','receive','issue','adjustment','transfer_in','transfer_out','sale') then raise exception 'Invalid movement type'; end if;
  if p_quantity = 0 then raise exception 'Quantity cannot be zero'; end if;

  select m.organization_id into v_org
  from public.memberships m
  where m.user_id = v_user and m.branch_id = p_branch_id and m.status = 'active'
  limit 1;
  if v_org is null then raise exception 'Active branch membership required'; end if;

  v_permission := case when p_movement_type in ('receive','opening') then 'inventory.receive' else 'inventory.adjust' end;
  if not public.has_permission(v_org, v_permission) then raise exception 'Inventory permission required'; end if;

  if not exists (select 1 from public.inventory_items i where i.id = p_inventory_item_id and i.organization_id = v_org and i.is_active) then
    raise exception 'Inventory item unavailable';
  end if;

  insert into public.stock_levels (organization_id, branch_id, inventory_item_id, quantity)
  values (v_org, p_branch_id, p_inventory_item_id, 0)
  on conflict (branch_id, inventory_item_id) do nothing;

  update public.stock_levels
  set quantity = quantity + p_quantity,
      updated_at = now()
  where branch_id = p_branch_id and inventory_item_id = p_inventory_item_id
  returning * into v_level;

  if v_level.quantity < 0 then raise exception 'Insufficient stock'; end if;

  insert into public.stock_movements (organization_id, branch_id, inventory_item_id, movement_type, quantity, unit_cost, reference, notes, created_by)
  values (v_org, p_branch_id, p_inventory_item_id, p_movement_type, p_quantity, greatest(coalesce(p_unit_cost,0),0), nullif(trim(p_reference),''), p_notes, v_user);

  return v_level;
end;
$$;

revoke all on function public.record_stock_movement(uuid,uuid,text,numeric,numeric,text,text) from public;
grant execute on function public.record_stock_movement(uuid,uuid,text,numeric,numeric,text,text) to authenticated;
