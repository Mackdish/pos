create or replace function public.create_restaurant_order(
  p_branch_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_order_type text,
  p_payment_method text,
  p_items jsonb,
  p_notes text default null
)
returns table (order_id uuid, order_number bigint, total_amount numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_order public.orders;
  v_item jsonb;
  v_product public.products;
  v_quantity numeric;
  v_subtotal numeric := 0;
  v_tax numeric := 0;
  v_discount numeric := 0;
  v_total numeric := 0;
  v_payment_status text;
  v_order_status text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_payment_method not in ('cash','mpesa','airtel_money','card','bank','credit') then
    raise exception 'Unsupported payment method';
  end if;

  if p_order_type not in ('dine_in','takeaway','delivery','room_service','counter') then
    raise exception 'Unsupported order type';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'At least one order item is required';
  end if;

  select m.organization_id
    into v_org_id
  from public.memberships m
  where m.user_id = v_user_id
    and m.branch_id = p_branch_id
    and m.status = 'active'
  limit 1;

  if v_org_id is null then
    raise exception 'Active branch membership required';
  end if;

  if not public.has_permission(v_org_id, 'orders.create') then
    raise exception 'You do not have permission to create orders';
  end if;

  insert into public.orders (
    organization_id,
    branch_id,
    customer_name,
    customer_phone,
    order_type,
    status,
    payment_status,
    created_by,
    notes
  ) values (
    v_org_id,
    p_branch_id,
    nullif(trim(coalesce(p_customer_name, '')), ''),
    nullif(trim(coalesce(p_customer_phone, '')), ''),
    p_order_type,
    case when p_payment_method = 'cash' then 'completed' else 'confirmed' end,
    case when p_payment_method = 'cash' then 'paid' else 'unpaid' end,
    v_user_id,
    p_notes
  ) returning * into v_order;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    select p.* into v_product
    from public.products p
    where p.id = (v_item->>'product_id')::uuid
      and p.organization_id = v_org_id
      and p.is_active = true;

    if v_product.id is null then
      raise exception 'Product % is unavailable', v_item->>'product_id';
    end if;

    v_quantity := greatest(coalesce((v_item->>'quantity')::numeric, 0), 0);
    if v_quantity <= 0 then
      raise exception 'Quantity must be greater than zero';
    end if;

    insert into public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      unit_price,
      discount_amount,
      tax_amount,
      line_total
    ) values (
      v_order.id,
      v_product.id,
      v_product.name,
      v_quantity,
      v_product.price,
      0,
      round((v_product.price * v_quantity) * (case when v_product.is_taxable then v_product.tax_rate else 0 end) / 100, 2),
      round((v_product.price * v_quantity) + ((v_product.price * v_quantity) * (case when v_product.is_taxable then v_product.tax_rate else 0 end) / 100), 2)
    );

    v_subtotal := v_subtotal + (v_product.price * v_quantity);
    v_tax := v_tax + round((v_product.price * v_quantity) * (case when v_product.is_taxable then v_product.tax_rate else 0 end) / 100, 2);
  end loop;

  v_total := greatest(v_subtotal + v_tax - v_discount, 0);
  v_payment_status := case when p_payment_method = 'cash' then 'paid' else 'unpaid' end;
  v_order_status := case when p_payment_method = 'cash' then 'completed' else 'confirmed' end;

  update public.orders
  set subtotal = v_subtotal,
      tax_amount = v_tax,
      discount_amount = v_discount,
      total_amount = v_total,
      payment_status = v_payment_status,
      status = v_order_status,
      completed_at = case when p_payment_method = 'cash' then now() else null end
  where id = v_order.id;

  insert into public.payments (
    organization_id,
    branch_id,
    order_id,
    amount,
    method,
    status,
    received_by,
    confirmed_at
  ) values (
    v_org_id,
    p_branch_id,
    v_order.id,
    v_total,
    p_payment_method,
    case when p_payment_method = 'cash' then 'confirmed' else 'pending' end,
    v_user_id,
    case when p_payment_method = 'cash' then now() else null end
  );

  return query select v_order.id, v_order.order_number, v_total;
end;
$$;

revoke all on function public.create_restaurant_order(uuid,text,text,text,text,jsonb,text) from public;
grant execute on function public.create_restaurant_order(uuid,text,text,text,text,jsonb,text) to authenticated;
