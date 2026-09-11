-- Cashier shifts, cash movements, expenses, discounts and controlled order actions.

insert into public.permissions (code, description) values
('cashbook.view','View cashier cashbook'),
('cashbook.manage','Manage cashier cash movements'),
('expenses.manage','Manage expenses'),
('refunds.manage','Process refunds'),
('voids.manage','Void orders and payments'),
('discounts.manage','Apply operational discounts')
on conflict (code) do nothing;

alter table public.payments add column if not exists shift_id uuid;

create table public.cash_shifts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  opened_by uuid not null references auth.users(id) on delete restrict,
  closed_by uuid references auth.users(id) on delete set null,
  status text not null default 'open' check (status in ('open','closed','reconciled')),
  opening_cash numeric(14,2) not null default 0 check (opening_cash >= 0),
  closing_cash numeric(14,2),
  expected_cash numeric(14,2),
  variance numeric(14,2),
  notes text,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index one_open_shift_per_branch on public.cash_shifts(branch_id) where status = 'open';
create index cash_shifts_branch_created_idx on public.cash_shifts(branch_id, created_at desc);
alter table public.payments add constraint payments_shift_fk foreign key (shift_id) references public.cash_shifts(id) on delete set null;

create table public.cash_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  shift_id uuid not null references public.cash_shifts(id) on delete restrict,
  movement_type text not null check (movement_type in ('cash_in','cash_out','float','refund')),
  amount numeric(14,2) not null check (amount > 0),
  reason text not null,
  reference text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index cash_movements_shift_idx on public.cash_movements(shift_id, created_at desc);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  shift_id uuid references public.cash_shifts(id) on delete set null,
  category text not null,
  description text not null,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text not null default 'cash' check (payment_method in ('cash','mpesa','airtel_money','card','bank')),
  status text not null default 'pending' check (status in ('pending','approved','rejected','paid')),
  requested_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  paid_at timestamptz,
  reference text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index expenses_branch_created_idx on public.expenses(branch_id, created_at desc);

create table public.order_adjustments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete restrict,
  adjustment_type text not null check (adjustment_type in ('discount','void','refund')),
  amount numeric(14,2) not null default 0 check (amount >= 0),
  reason text not null,
  approved_by uuid references auth.users(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index order_adjustments_order_idx on public.order_adjustments(order_id, created_at desc);

create trigger cash_shifts_updated_at before update on public.cash_shifts for each row execute function public.set_updated_at();
create trigger expenses_updated_at before update on public.expenses for each row execute function public.set_updated_at();

alter table public.cash_shifts enable row level security;
alter table public.cash_movements enable row level security;
alter table public.expenses enable row level security;
alter table public.order_adjustments enable row level security;

create policy cash_shifts_select on public.cash_shifts for select to authenticated using (public.is_org_member(organization_id));
create policy cash_movements_select on public.cash_movements for select to authenticated using (public.is_org_member(organization_id));
create policy expenses_select on public.expenses for select to authenticated using (public.is_org_member(organization_id));
create policy expenses_insert on public.expenses for insert to authenticated with check (public.has_permission(organization_id,'expenses.manage'));
create policy expenses_update on public.expenses for update to authenticated using (public.has_permission(organization_id,'expenses.approve') or public.has_permission(organization_id,'expenses.manage')) with check (public.has_permission(organization_id,'expenses.approve') or public.has_permission(organization_id,'expenses.manage'));
create policy adjustments_select on public.order_adjustments for select to authenticated using (public.is_org_member(organization_id));

create or replace function public.open_cash_shift(p_branch_id uuid, p_opening_cash numeric, p_notes text default null)
returns public.cash_shifts language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); v_org uuid; v_shift public.cash_shifts;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select organization_id into v_org from public.memberships where user_id=v_user and branch_id=p_branch_id and status='active' limit 1;
 if v_org is null then raise exception 'Active branch membership required'; end if;
 if not public.has_permission(v_org,'shifts.open') then raise exception 'Shift opening permission required'; end if;
 if p_opening_cash < 0 then raise exception 'Opening cash cannot be negative'; end if;
 if exists(select 1 from public.cash_shifts where branch_id=p_branch_id and status='open') then raise exception 'A shift is already open for this branch'; end if;
 insert into public.cash_shifts(organization_id,branch_id,opened_by,opening_cash,notes) values(v_org,p_branch_id,v_user,p_opening_cash,p_notes) returning * into v_shift;
 insert into public.cash_movements(organization_id,branch_id,shift_id,movement_type,amount,reason,created_by) values(v_org,p_branch_id,v_shift.id,'float',p_opening_cash,'Opening float',v_user);
 return v_shift;
end; $$;

create or replace function public.close_cash_shift(p_shift_id uuid, p_closing_cash numeric, p_notes text default null)
returns public.cash_shifts language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); v_shift public.cash_shifts; v_expected numeric; v_org uuid;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_shift from public.cash_shifts where id=p_shift_id for update;
 if v_shift.id is null then raise exception 'Shift not found'; end if;
 v_org:=v_shift.organization_id;
 if not public.is_org_member(v_org) then raise exception 'Not authorized'; end if;
 if not public.has_permission(v_org,'shifts.close') then raise exception 'Shift closing permission required'; end if;
 if v_shift.status <> 'open' then raise exception 'Shift is already closed'; end if;
 if p_closing_cash < 0 then raise exception 'Closing cash cannot be negative'; end if;
 select v_shift.opening_cash + coalesce((select sum(case when movement_type in ('cash_in','float') then amount when movement_type in ('cash_out','refund') then -amount else 0 end) from public.cash_movements where shift_id=v_shift.id),0) + coalesce((select sum(amount) from public.payments where shift_id=v_shift.id and method='cash' and status='confirmed'),0) into v_expected;
 update public.cash_shifts set status='closed',closed_by=v_user,closed_at=now(),closing_cash=p_closing_cash,expected_cash=round(v_expected,2),variance=round(p_closing_cash-v_expected,2),notes=coalesce(p_notes,notes),updated_at=now() where id=v_shift.id returning * into v_shift;
 return v_shift;
end; $$;

create or replace function public.record_cash_movement(p_shift_id uuid,p_type text,p_amount numeric,p_reason text,p_reference text default null)
returns public.cash_movements language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); v_shift public.cash_shifts; v_org uuid; v_move public.cash_movements;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_shift from public.cash_shifts where id=p_shift_id for update;
 if v_shift.id is null or v_shift.status <> 'open' then raise exception 'Open shift required'; end if;
 v_org:=v_shift.organization_id;
 if not public.has_permission(v_org,'cashbook.manage') then raise exception 'Cashbook permission required'; end if;
 if p_type not in ('cash_in','cash_out') then raise exception 'Invalid cash movement type'; end if;
 if p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;
 insert into public.cash_movements(organization_id,branch_id,shift_id,movement_type,amount,reason,reference,created_by) values(v_org,v_shift.branch_id,p_shift_id,p_type,p_amount,trim(p_reason),nullif(trim(p_reference),''),v_user) returning * into v_move;
 return v_move;
end; $$;

create or replace function public.apply_order_discount(p_order_id uuid,p_amount numeric,p_reason text)
returns public.orders language plpgsql security definer set search_path=public as $$
declare v_order public.orders; v_user uuid:=auth.uid(); v_org uuid;
begin
 select * into v_order from public.orders where id=p_order_id for update;
 if v_order.id is null then raise exception 'Order not found'; end if; v_org:=v_order.organization_id;
 if not public.has_permission(v_org,'discounts.manage') then raise exception 'Discount permission required'; end if;
 if p_amount <= 0 or p_amount > v_order.subtotal + v_order.tax_amount then raise exception 'Invalid discount amount'; end if;
 update public.orders set discount_amount=p_amount,total_amount=greatest(subtotal+tax_amount-p_amount,0) where id=v_order.id returning * into v_order;
 insert into public.order_adjustments(organization_id,branch_id,order_id,adjustment_type,amount,reason,created_by) values(v_org,v_order.branch_id,p_order_id,'discount',p_amount,trim(p_reason),v_user);
 return v_order;
end; $$;

create or replace function public.void_order(p_order_id uuid,p_reason text)
returns public.orders language plpgsql security definer set search_path=public as $$
declare v_order public.orders; v_user uuid:=auth.uid();
begin
 select * into v_order from public.orders where id=p_order_id for update;
 if v_order.id is null then raise exception 'Order not found'; end if;
 if not public.has_permission(v_order.organization_id,'voids.manage') then raise exception 'Void permission required'; end if;
 if v_order.status in ('cancelled','voided') then raise exception 'Order is already voided'; end if;
 update public.orders set status='voided',payment_status='voided' where id=v_order.id returning * into v_order;
 insert into public.order_adjustments(organization_id,branch_id,order_id,adjustment_type,amount,reason,created_by) values(v_order.organization_id,v_order.branch_id,p_order_id,'void',v_order.total_amount,trim(p_reason),v_user);
 return v_order;
end; $$;

revoke all on function public.open_cash_shift(uuid,numeric,text),public.close_cash_shift(uuid,numeric,text),public.record_cash_movement(uuid,text,numeric,text,text),public.apply_order_discount(uuid,numeric,text),public.void_order(uuid,text) from public;
grant execute on function public.open_cash_shift(uuid,numeric,text),public.close_cash_shift(uuid,numeric,text),public.record_cash_movement(uuid,text,numeric,text,text),public.apply_order_discount(uuid,numeric,text),public.void_order(uuid,text) to authenticated;
