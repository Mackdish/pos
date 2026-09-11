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
  product_type text not null default 'food' check (product_type in ('food','beverage','service','room_charge','other')),
  selling_price numeric(12,2) not null default 0 check (selling_price >= 0),
  cost_price numeric(12,2) not null default 0 check (cost_price >= 0),
  tax_rate numeric(6,3) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  is_taxable boolean not null default false,
  track_inventory boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, sku)
);

create table public.restaurant_tables (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete cascade,
  table_number text not null,
  name text,
  capacity integer not null default 2 check (capacity > 0),
  status text not null default 'available' check (status in ('available','occupied','reserved','maintenance')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, branch_id, table_number)
);

create sequence public.order_number_seq;

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete restrict,
  order_number bigint not null default nextval('public.order_number_seq'),
  order_type text not null default 'restaurant' check (order_type in ('restaurant','takeaway','room_service','room_charge','other')),
  status text not null default 'open' check (status in ('open','pending_payment','preparing','ready','served','completed','cancelled','refunded')),
  customer_name text,
  customer_phone text,
  room_reference text,
  table_id uuid references public.restaurant_tables(id) on delete set null,
  notes text,
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  discount_amount numeric(12,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(12,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(12,2) not null default 0 check (total_amount >= 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, order_number)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  unit_price numeric(12,2) not null check (unit_price >= 0),
  quantity numeric(12,3) not null check (quantity > 0),
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
  payment_method text not null check (payment_method in ('cash','mpesa','airtel_money','card','bank','credit','other')),
  status text not null default 'pending' check (status in ('pending','confirmed','failed','refunded','voided')),
  amount numeric(12,2) not null check (amount > 0),
  reference text,
  external_reference text,
  paid_at timestamptz,
  received_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index categories_org_idx on public.categories(organization_id, is_active);
create index products_org_category_idx on public.products(organization_id, category_id, is_active);
create index products_org_name_idx on public.products(organization_id, name);
create index tables_org_branch_idx on public.restaurant_tables(organization_id, branch_id, is_active);
create index orders_org_created_idx on public.orders(organization_id, created_at desc);
create index orders_branch_created_idx on public.orders(branch_id, created_at desc);
create index orders_status_idx on public.orders(organization_id, status);
create index order_items_order_idx on public.order_items(order_id);
create index payments_order_idx on public.payments(order_id);
create index payments_org_created_idx on public.payments(organization_id, created_at desc);
create index payments_reference_idx on public.payments(reference) where reference is not null;

create trigger categories_updated_at before update on public.categories for each row execute function public.set_updated_at();
create trigger products_updated_at before update on public.products for each row execute function public.set_updated_at();
create trigger restaurant_tables_updated_at before update on public.restaurant_tables for each row execute function public.set_updated_at();
create trigger orders_updated_at before update on public.orders for each row execute function public.set_updated_at();
create trigger payments_updated_at before update on public.payments for each row execute function public.set_updated_at();

alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.restaurant_tables enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;

create policy categories_select on public.categories for select to authenticated using (public.is_org_member(organization_id));
create policy categories_insert on public.categories for insert to authenticated with check (public.has_permission(organization_id,'products.create'));
create policy categories_update on public.categories for update to authenticated using (public.has_permission(organization_id,'products.update')) with check (public.has_permission(organization_id,'products.update'));
create policy categories_delete on public.categories for delete to authenticated using (public.has_permission(organization_id,'products.delete'));

create policy products_select on public.products for select to authenticated using (public.is_org_member(organization_id));
create policy products_insert on public.products for insert to authenticated with check (public.has_permission(organization_id,'products.create'));
create policy products_update on public.products for update to authenticated using (public.has_permission(organization_id,'products.update')) with check (public.has_permission(organization_id,'products.update'));
create policy products_delete on public.products for delete to authenticated using (public.has_permission(organization_id,'products.delete'));

create policy tables_select on public.restaurant_tables for select to authenticated using (public.is_org_member(organization_id));
create policy tables_insert on public.restaurant_tables for insert to authenticated with check (public.has_permission(organization_id,'rooms.manage'));
create policy tables_update on public.restaurant_tables for update to authenticated using (public.has_permission(organization_id,'rooms.manage')) with check (public.has_permission(organization_id,'rooms.manage'));
create policy tables_delete on public.restaurant_tables for delete to authenticated using (public.has_permission(organization_id,'rooms.manage'));

create policy orders_select on public.orders for select to authenticated using (public.is_org_member(organization_id));
create policy orders_insert on public.orders for insert to authenticated with check (public.has_permission(organization_id,'orders.create'));
create policy orders_update on public.orders for update to authenticated using (public.has_permission(organization_id,'orders.update')) with check (public.has_permission(organization_id,'orders.update'));
create policy orders_cancel on public.orders for update to authenticated using (status <> 'cancelled' and public.has_permission(organization_id,'orders.cancel')) with check (status = 'cancelled');

create policy order_items_select on public.order_items for select to authenticated using (
  exists (select 1 from public.orders o where o.id = order_items.order_id and public.is_org_member(o.organization_id))
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

create policy payments_select on public.payments for select to authenticated using (public.is_org_member(organization_id));
create policy payments_insert on public.payments for insert to authenticated with check (public.has_permission(organization_id,'payments.create'));
create policy payments_update on public.payments for update to authenticated using (public.has_permission(organization_id,'payments.verify')) with check (public.has_permission(organization_id,'payments.verify'));

insert into public.categories (organization_id, name, description)
select o.id, c.name, c.description
from public.organizations o
cross join (values
  ('Mains','Main meals'),
  ('Sides','Side dishes'),
  ('Drinks','Beverages'),
  ('Breakfast','Breakfast items')
) as c(name, description)
where not exists (select 1 from public.categories x where x.organization_id = o.id and x.name = c.name);
