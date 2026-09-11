-- Correct expected-cash calculation: opening_cash is already the opening balance,
-- so the opening float movement must not be counted a second time.
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
 select v_shift.opening_cash
   + coalesce((select sum(case when movement_type='cash_in' then amount when movement_type in ('cash_out','refund') then -amount else 0 end) from public.cash_movements where shift_id=v_shift.id),0)
   + coalesce((select sum(amount) from public.payments where shift_id=v_shift.id and method='cash' and status='confirmed'),0)
   - coalesce((select sum(e.amount) from public.expenses e where e.shift_id=v_shift.id and e.payment_method='cash' and e.status='paid'),0)
 into v_expected;
 update public.cash_shifts set status='closed',closed_by=v_user,closed_at=now(),closing_cash=p_closing_cash,expected_cash=round(v_expected,2),variance=round(p_closing_cash-v_expected,2),notes=coalesce(p_notes,notes),updated_at=now() where id=v_shift.id returning * into v_shift;
 return v_shift;
end; $$;

grant execute on function public.close_cash_shift(uuid,numeric,text) to authenticated;

-- Payments created before a shift exists remain unassigned. Cash sales now require
-- an open shift in the atomic order function; this index supports reconciliation.
create index if not exists payments_shift_cash_idx on public.payments(shift_id, method, status) where shift_id is not null;
create index if not exists expenses_shift_cash_idx on public.expenses(shift_id, payment_method, status) where shift_id is not null;
