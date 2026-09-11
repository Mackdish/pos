-- Production financial controls: audited discounts, voids, refunds, expense approval/payment.
-- All money-changing actions are server-side, permission checked and append an audit record.

create or replace function public.apply_order_discount(p_order_id uuid,p_amount numeric,p_reason text)
returns public.orders language plpgsql security definer set search_path=public as $$
declare v_order public.orders; v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if v_order.id is null then raise exception 'Order not found'; end if;
 if not public.has_permission(v_order.organization_id,'discounts.manage') then raise exception 'Discount permission required'; end if;
 if v_order.payment_status in ('paid','refunded','voided') or v_order.status in ('completed','cancelled','voided') then
   raise exception 'Discounts cannot be applied after payment or completion';
 end if;
 if p_amount <= 0 or p_amount > v_order.subtotal + v_order.tax_amount then raise exception 'Invalid discount amount'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Discount reason is required'; end if;
 update public.orders
 set discount_amount=p_amount,
     total_amount=greatest(subtotal+tax_amount-p_amount,0)
 where id=v_order.id
 returning * into v_order;
 insert into public.order_adjustments(organization_id,branch_id,order_id,adjustment_type,amount,reason,created_by)
 values(v_order.organization_id,v_order.branch_id,p_order_id,'discount',p_amount,trim(p_reason),v_user);
 insert into public.audit_logs(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,new_data,metadata)
 values(v_order.organization_id,v_order.branch_id,v_user_id,'discount.applied','order',p_order_id::text,to_jsonb(v_order),jsonb_build_object('amount',p_amount,'reason',trim(p_reason)));
 return v_order;
end; $$;

create or replace function public.void_order(p_order_id uuid,p_reason text)
returns public.orders language plpgsql security definer set search_path=public as $$
declare v_order public.orders; v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if v_order.id is null then raise exception 'Order not found'; end if;
 if not public.has_permission(v_order.organization_id,'voids.manage') then raise exception 'Void permission required'; end if;
 if v_order.status in ('cancelled','voided') then raise exception 'Order is already voided'; end if;
 if v_order.payment_status in ('paid','refunded') then raise exception 'Paid orders must be refunded instead of voided'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Void reason is required'; end if;
 update public.orders set status='voided',payment_status='voided' where id=v_order.id returning * into v_order;
 insert into public.order_adjustments(organization_id,branch_id,order_id,adjustment_type,amount,reason,created_by)
 values(v_order.organization_id,v_order.branch_id,p_order_id,'void',v_order.total_amount,trim(p_reason),v_user);
 insert into public.audit_logs(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,old_data,new_data,metadata)
 values(v_order.organization_id,v_order.branch_id,v_user_id,'order.voided','order',p_order_id::text,to_jsonb(v_order),to_jsonb(v_order),jsonb_build_object('reason',trim(p_reason)));
 return v_order;
end; $$;

create or replace function public.refund_order(p_order_id uuid,p_amount numeric,p_reason text,p_reference text default null)
returns public.orders language plpgsql security definer set search_path=public as $$
declare
 v_order public.orders; v_payment public.payments; v_user uuid:=auth.uid(); v_paid numeric; v_refunded numeric; v_remaining numeric;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if v_order.id is null then raise exception 'Order not found'; end if;
 if not public.has_permission(v_order.organization_id,'refunds.manage') then raise exception 'Refund permission required'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Refund reason is required'; end if;
 select coalesce(sum(amount),0) into v_paid from public.payments where order_id=p_order_id and status='confirmed';
 select coalesce(sum(amount),0) into v_refunded from public.order_adjustments where order_id=p_order_id and adjustment_type='refund';
 v_remaining:=greatest(v_paid-v_refunded,0);
 if p_amount <= 0 or p_amount > v_remaining then raise exception 'Refund exceeds refundable amount'; end if;
 if p_reference is null and exists(select 1 from public.payments where order_id=p_order_id and status='confirmed' and method <> 'cash') then
   raise exception 'External refund reference is required for non-cash refunds';
 end if;
 select * into v_payment from public.payments where order_id=p_order_id and status='confirmed' order by created_at desc limit 1 for update;
 if v_payment.id is null then raise exception 'No confirmed payment found'; end if;
 if v_payment.method='cash' then
   if not exists(select 1 from public.cash_shifts where branch_id=v_order.branch_id and status='open') then raise exception 'Open cash shift required for cash refund'; end if;
   insert into public.cash_movements(organization_id,branch_id,shift_id,movement_type,amount,reason,reference,created_by)
   select v_order.organization_id,v_order.branch_id,id,'refund',p_amount,trim(p_reason),nullif(trim(p_reference),''),v_user
   from public.cash_shifts where branch_id=v_order.branch_id and status='open';
 end if;
 insert into public.order_adjustments(organization_id,branch_id,order_id,adjustment_type,amount,reason,approved_by,created_by)
 values(v_order.organization_id,v_order.branch_id,p_order_id,'refund',p_amount,trim(p_reason),v_user,v_user);
 if p_amount >= v_remaining then
   update public.payments set status='refunded',reference=coalesce(nullif(trim(p_reference),''),reference),updated_at=now() where order_id=p_order_id and status='confirmed';
   update public.orders set payment_status='refunded',status=case when status <> 'voided' then 'completed' else status end where id=p_order_id returning * into v_order;
 else
   update public.orders set payment_status='partial' where id=p_order_id returning * into v_order;
 end if;
 insert into public.audit_logs(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,new_data,metadata)
 values(v_order.organization_id,v_order.branch_id,v_user_id,'order.refunded','order',p_order_id::text,to_jsonb(v_order),jsonb_build_object('amount',p_amount,'reason',trim(p_reason),'reference',p_reference));
 return v_order;
end; $$;

create or replace function public.approve_expense(p_expense_id uuid,p_notes text default null)
returns public.expenses language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); v_expense public.expenses;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_expense from public.expenses where id=p_expense_id for update;
 if v_expense.id is null then raise exception 'Expense not found'; end if;
 if not public.has_permission(v_expense.organization_id,'expenses.approve') then raise exception 'Expense approval permission required'; end if;
 if v_expense.status <> 'pending' then raise exception 'Only pending expenses can be approved'; end if;
 update public.expenses set status='approved',approved_by=v_user,approved_at=now(),notes=coalesce(p_notes,notes),updated_at=now() where id=p_expense_id returning * into v_expense;
 insert into public.audit_logs(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,new_data)
 values(v_expense.organization_id,v_expense.branch_id,v_user,'expense.approved','expense',p_expense_id::text,to_jsonb(v_expense));
 return v_expense;
end; $$;

create or replace function public.pay_expense(p_expense_id uuid,p_shift_id uuid default null,p_reference text default null)
returns public.expenses language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); v_expense public.expenses; v_shift public.cash_shifts;
begin
 if v_user is null then raise exception 'Authentication required'; end if;
 select * into v_expense from public.expenses where id=p_expense_id for update;
 if v_expense.id is null then raise exception 'Expense not found'; end if;
 if not public.has_permission(v_expense.organization_id,'expenses.manage') then raise exception 'Expense management permission required'; end if;
 if v_expense.status <> 'approved' then raise exception 'Only approved expenses can be paid'; end if;
 if v_expense.payment_method='cash' then
   select * into v_shift from public.cash_shifts where id=coalesce(p_shift_id,v_expense.shift_id) and status='open' for update;
   if v_shift.id is null or v_shift.branch_id <> v_expense.branch_id then raise exception 'Open branch cash shift required'; end if;
   insert into public.cash_movements(organization_id,branch_id,shift_id,movement_type,amount,reason,reference,created_by)
   values(v_expense.organization_id,v_expense.branch_id,v_shift.id,'cash_out',v_expense.amount,'Expense: '||v_expense.description,nullif(trim(coalesce(p_reference,v_expense.reference)),''),v_user);
   update public.expenses set status='paid',shift_id=v_shift.id,paid_at=now(),reference=coalesce(nullif(trim(p_reference),''),reference),updated_at=now() where id=p_expense_id returning * into v_expense;
 else
   update public.expenses set status='paid',paid_at=now(),reference=coalesce(nullif(trim(p_reference),''),reference),updated_at=now() where id=p_expense_id returning * into v_expense;
 end if;
 insert into public.audit_logs(organization_id,branch_id,actor_user_id,action,entity_type,entity_id,new_data)
 values(v_expense.organization_id,v_expense.branch_id,v_user,'expense.paid','expense',p_expense_id::text,to_jsonb(v_expense));
 return v_expense;
end; $$;

revoke all on function public.apply_order_discount(uuid,numeric,text),public.void_order(uuid,text),public.refund_order(uuid,numeric,text,text),public.approve_expense(uuid,text),public.pay_expense(uuid,uuid,text) from public;
grant execute on function public.apply_order_discount(uuid,numeric,text),public.void_order(uuid,text),public.refund_order(uuid,numeric,text,text),public.approve_expense(uuid,text),public.pay_expense(uuid,uuid,text) to authenticated;

create index if not exists audit_logs_entity_idx on public.audit_logs(entity_type,entity_id,created_at desc);
