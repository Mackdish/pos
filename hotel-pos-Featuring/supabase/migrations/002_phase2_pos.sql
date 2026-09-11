create table public.categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  code text not null,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  sku text,
  name text not null,
  description text,
  product_type text not null default 'menu_item' check (product_type in ('menu_item','room_charge','service','retail')),
  unit text not null default 'each',
  selling_price numeric(14,2) not null default 0 check (selling_price >= 0),
  cost_price numeric(14,2) not null default 0 check (cost_price >= 0),
  tax_rate numeric(6,3) not null default 0 check (tax_rate >= 0),
  track_inventory boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, sku)
);

create table public.tables (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  name text not null,
  capacity integer not null default 2 check (capacity > 0),
  status text not null default 'available' check (status in ('available','occupied','reserved','out_of_service')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, name)
);

create sequence public.order_number_seq start 1001;

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  order_number bigint not null default nextval('public.order_number_seq'),
  order_type text not null default 'restaurant' check (order_type in ('restaurant','takeaway','room_service','retail')),
  table_id uuid references public.tables(id) on delete set null,
  customer_name text,
  customer_phone text,
  room_number text,
  status text not null default 'open' check (status in ('open','sent_to_kitchen','preparing','ready','served','completed','cancelled','voided')),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid','partial','paid','refunded')),
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, branch_id, order_number)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete restrict,
  product_name text not null,
  unit_price numeric(14,2) not null check (unit_price >= 0),
  quantity numeric(12,3) not null check (quantity > 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  payment_method text not null check (payment_method in ('cash','mpesa','card','bank','airtel_money','other')),
  amount numeric(14,2) not null check (amount > 0),
  status text not null default 'pending' check (status in ('pending','completed','failed','cancelled','refunded')),
  reference text,
  external_reference text,
  phone_number text,
  received_by uuid references auth.users(id) on delete set null,
  paid_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index payments_external_reference_uq on public.payments(external_reference) where external_reference is not null;
create index categories_org_idx on public.categories(organization_id);
create index products_org_idx on public.products(organization_id);
create index products_category_idx on public.products(category_id);
create index tables_branch_idx on public.tables(branch_id);
create index orders_org_created_idx on public.orders(organization_id, created_at desc);
create index orders_branch_status_idx on public.orders(branch_id, status, created_at desc);
create index orders_table_idx on public.orders(table_id);
create index order_items_order_idx on public.order_items(order_id);
create index payments_order_idx on public.payments(order_id);
create index payments_branch_created_idx on public.payments(branch_id, created_at desc);
create index payments_status_idx on public.payments(status);

create trigger categories_updated_at before update on public.categories for each row execute function public.set_updated_at();
create trigger products_updated_at before update on public.products for each row execute function public.set_updated_at();
create trigger tables_updated_at before update on public.tables for each row execute function public.set_updated_at();
create trigger orders_updated_at before update on public.orders for each row execute function public.set_updated_at();
create trigger order_items_updated_at before update on public.order_items for each row execute function public.set_updated_at();
create trigger payments_updated_at before update on public.payments for each row execute function public.set_updated_at();

alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.tables enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;

create policy categories_select on public.categories for select to authenticated using (public.is_org_member(organization_id));
create policy categories_manage on public.categories for all to authenticated using (public.has_permission(organization_id,'products.create') or public.has_permission(organization_id,'products.update')) with check (public.has_permission(organization_id,'products.create') or public.has_permission(organization_id,'products.update'));

create policy products_select on public.products for select to authenticated using (public.is_org_member(organization_id));
create policy products_insert on public.products for insert to authenticated with check (public.has_permission(organization_id,'products.create'));
create policy products_update on public.products for update to authenticated using (public.has_permission(organization_id,'products.update')) with check (public.has_permission(organization_id,'products.update'));
create policy products_delete on public.products for delete to authenticated using (public.has_permission(organization_id,'products.delete'));

create policy tables_select on public.tables for select to authenticated using (public.is_org_member(organization_id));
create policy tables_manage on public.tables for all to authenticated using (public.has_permission(organization_id,'rooms.manage')) with check (public.has_permission(organization_id,'rooms.manage'));

create policy orders_select on public.orders for select to authenticated using (public.has_permission(organization_id,'orders.view'));
create policy orders_insert on public.orders for insert to authenticated with check (public.has_permission(organization_id,'orders.create') and public.is_org_member(organization_id));
create policy orders_update on public.orders for update to authenticated using (public.has_permission(organization_id,'orders.update')) with check (public.has_permission(organization_id,'orders.update'));
create policy orders_cancel on public.orders for delete to authenticated using (public.has_permission(organization_id,'orders.cancel'));

create policy order_items_select on public.order_items for select to authenticated using (
  exists (select 1 from public.orders o where o.id = order_items.order_id and public.has_permission(o.organization_id,'orders.view'))
);
create policy order_items_insert on public.order_items for insert to authenticated with check (
  exists (select 1 from public.orders o where o.id = order_items.order_id and public.has_permission(o.organization_id,'orders.create'))
);
create policy order_items_update on public.order_items for update to authenticated using (
  exists (select 1 from public.orders o where o.id = order_items.order_id and public.has_permission(o.organization_id,'orders.update'))
) with check (
  exists (select 1 from public.orders o where o.id = order_items.order_id and public.has_permission(o.organization_id,'orders.update'))
);
create policy order_items_delete on public.order_items for delete to authenticated using (
  exists (select 1 from public.orders o where o.id = order_items.order_id and public.has_permission(o.organization_id,'orders.update'))
);

create policy payments_select on public.payments for select to authenticated using (public.has_permission(organization_id,'orders.view'));
create policy payments_insert on public.payments for insert to authenticated with check (public.has_permission(organization_id,'payments.create') and public.is_org_member(organization_id));
create policy payments_update on public.payments for update to authenticated using (public.has_permission(organization_id,'payments.verify')) with check (public.has_permission(organization_id,'payments.verify'));

create or replace function public.recalculate_order_totals(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subtotal numeric(14,2);
  v_discount numeric(14,2);
  v_tax numeric(14,2);
begin
  select coalesce(sum(line_total),0), coalesce(sum(discount_amount),0), coalesce(sum(tax_amount),0)
    into v_subtotal, v_discount, v_tax
  from public.order_items
  where order_id = p_order_id;

  update public.orders
  set subtotal = v_subtotal,
      discount_amount = v_discount,
      tax_amount = v_tax,
      total_amount = greatest(v_subtotal - v_discount + v_tax, 0),
      updated_at = now()
  where id = p_order_id;
end;
$$;

revoke execute on function public.recalculate_order_totals(uuid) from public;
grant execute on function public.recalculate_order_totals(uuid) to authenticated;
