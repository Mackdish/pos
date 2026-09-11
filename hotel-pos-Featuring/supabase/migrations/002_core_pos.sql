create table public.categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, name)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  sku text,
  name text not null,
  description text,
  price numeric(12,2) not null default 0 check (price >= 0),
  cost_price numeric(12,2) check (cost_price is null or cost_price >= 0),
  tax_rate numeric(5,2) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  is_taxable boolean not null default false,
  product_type text not null default 'food' check (product_type in ('food','beverage','service','other')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, sku)
);

create table public.restaurant_tables (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  name text not null,
  capacity integer not null default 2 check (capacity > 0),
  status text not null default 'available' check (status in ('available','occupied','reserved','blocked')),
  area text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete restrict,
  order_number bigint generated always as identity,
  customer_name text,
  customer_phone text,
  room_number text,
  table_id uuid references public.restaurant_tables(id) on delete set null,
  order_type text not null default 'dine_in' check (order_type in ('dine_in','takeaway','delivery','room_service','counter')),
  status text not null default 'open' check (status in ('open','confirmed','preparing','ready','served','completed','cancelled','voided')),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid','partial','paid','refunded','voided')),
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  discount_amount numeric(12,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(12,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(12,2) not null default 0 check (total_amount >= 0),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  quantity numeric(10,2) not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  discount_amount numeric(12,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(12,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(12,2) not null check (line_total >= 0),
  notes text,
  created_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  method text not null check (method in ('cash','mpesa','airtel_money','card','bank','credit')),
  status text not null default 'pending' check (status in ('pending','confirmed','failed','refunded','voided')),
  reference text,
  phone_number text,
  provider text,
  metadata jsonb not null default '{}'::jsonb,
  received_by uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index products_org_sku_uq on public.products(organization_id, sku) where sku is not null;
create index categories_org_idx on public.categories(organization_id);
create index products_org_idx on public.products(organization_id);
create index products_category_idx on public.products(category_id);
create index tables_org_branch_idx on public.restaurant_tables(organization_id, branch_id);
create index orders_org_created_idx on public.orders(organization_id, created_at desc);
create index orders_branch_created_idx on public.orders(branch_id, created_at desc);
create index orders_status_idx on public.orders(organization_id, status, created_at desc);
create index order_items_order_idx on public.order_items(order_id);
create index payments_order_idx on public.payments(order_id);
create index payments_org_created_idx on public.payments(organization_id, created_at desc);

create trigger categories_updated_at before update on public.categories for each row execute function public.set_updated_at();
create trigger products_updated_at before update on public.products for each row execute function public.set_updated_at();
create trigger restaurant_tables_updated_at before update on public.restaurant_tables for each row execute function public.set_updated_at();
create trigger orders_updated_at before update on public.orders for each row execute function public.set_updated_at();
create trigger payments_updated_at before update on public.payments for each row execute function public.set_updated_at();

create or replace function public.recalculate_order_totals(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
begin
  update public.orders o
  set subtotal = coalesce(x.subtotal,0),
      tax_amount = coalesce(x.tax_amount,0),
      discount_amount = coalesce(x.discount_amount,0),
      total_amount = greatest(coalesce(x.subtotal,0) + coalesce(x.tax_amount,0) - coalesce(x.discount_amount,0),0)
  from (
    select oi.order_id,
           sum(oi.unit_price * oi.quantity) as subtotal,
           sum(oi.tax_amount) as tax_amount,
           sum(oi.discount_amount) as discount_amount
    from public.order_items oi
    where oi.order_id = p_order_id
    group by oi.order_id
  ) x
  where o.id = p_order_id
  returning o.* into v_order;

  if v_order.id is null then
    raise exception 'Order not found';
  end if;
  return v_order;
end;
$$;

alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.restaurant_tables enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;

create policy categories_select on public.categories for select to authenticated using (public.is_org_member(organization_id));
create policy categories_manage on public.categories for all to authenticated using (public.has_permission(organization_id,'products.create')) with check (public.has_permission(organization_id,'products.create'));

create policy products_select on public.products for select to authenticated using (public.is_org_member(organization_id));
create policy products_insert on public.products for insert to authenticated with check (public.has_permission(organization_id,'products.create'));
create policy products_update on public.products for update to authenticated using (public.has_permission(organization_id,'products.update')) with check (public.has_permission(organization_id,'products.update'));
create policy products_delete on public.products for delete to authenticated using (public.has_permission(organization_id,'products.delete'));

create policy tables_select on public.restaurant_tables for select to authenticated using (public.is_org_member(organization_id));
create policy tables_manage on public.restaurant_tables for all to authenticated using (public.has_permission(organization_id,'rooms.manage')) with check (public.has_permission(organization_id,'rooms.manage'));

create policy orders_select on public.orders for select to authenticated using (public.is_org_member(organization_id));
create policy orders_insert on public.orders for insert to authenticated with check (public.has_permission(organization_id,'orders.create'));
create policy orders_update on public.orders for update to authenticated using (public.has_permission(organization_id,'orders.update')) with check (public.has_permission(organization_id,'orders.update'));
create policy orders_cancel on public.orders for delete to authenticated using (public.has_permission(organization_id,'orders.cancel'));

create policy order_items_select on public.order_items for select to authenticated using (exists (select 1 from public.orders o where o.id = order_items.order_id and public.is_org_member(o.organization_id)));
create policy order_items_manage on public.order_items for all to authenticated using (exists (select 1 from public.orders o where o.id = order_items.order_id and public.has_permission(o.organization_id,'orders.update'))) with check (exists (select 1 from public.orders o where o.id = order_items.order_id and public.has_permission(o.organization_id,'orders.update')));

create policy payments_select on public.payments for select to authenticated using (public.is_org_member(organization_id));
create policy payments_insert on public.payments for insert to authenticated with check (public.has_permission(organization_id,'payments.create'));
create policy payments_update on public.payments for update to authenticated using (public.has_permission(organization_id,'payments.verify')) with check (public.has_permission(organization_id,'payments.verify'));
