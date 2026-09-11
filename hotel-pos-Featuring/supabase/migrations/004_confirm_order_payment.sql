create or replace function public.confirm_order_payment(p_order_id uuid, p_reference text default null)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_order public.orders;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;

  select o.* into v_order from public.orders o where o.id = p_order_id for update;
  if v_order.id is null then raise exception 'Order not found'; end if;

  v_org_id := v_order.organization_id;
  if not public.is_org_member(v_org_id) then raise exception 'Organization membership required'; end if;
  if not public.has_permission(v_org_id, 'payments.verify') then raise exception 'You do not have permission to verify payments'; end if;

  update public.payments
  set status = 'confirmed', reference = coalesce(nullif(trim(p_reference), ''), reference), confirmed_at = now(), updated_at = now()
  where order_id = p_order_id and status = 'pending';

  if not found then raise exception 'No pending payment exists for this order'; end if;

  update public.orders
  set payment_status = 'paid', status = case when status in ('confirmed','open','ready','served') then 'completed' else status end, completed_at = coalesce(completed_at, now()), updated_at = now()
  where id = p_order_id
  returning * into v_order;

  return v_order;
end;
$$;

revoke all on function public.confirm_order_payment(uuid,text) from public;
grant execute on function public.confirm_order_payment(uuid,text) to authenticated;
