import { createClient } from './supabase/client';

export async function getProducts() {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('products')
    .select('id, sku, name, description, price, category_id, is_active, categories(id,name)')
    .eq('is_active', true)
    .order('name');
  if (error) throw error;
  return data ?? [];
}

export async function getOrders({ limit = 100 } = {}) {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('orders')
    .select('id, order_number, customer_name, order_type, status, subtotal, discount_amount, tax_amount, total, created_at, payment_status, payment_method, profiles:user_id(first_name,last_name)')
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data ?? [];
}

export async function getOrder(id) {
  const supabase = createClient();
  const { data, error } = await supabase
    .from('orders')
    .select('*, profiles:user_id(first_name,last_name), order_items(*, products(id,sku,name))')
    .eq('id', id)
    .single();
  if (error) throw error;
  return data;
}

export async function createOrder({ customerName = 'Walk-in customer', items, paymentMethod = 'cash' }) {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('You must be signed in to create an order.');
  if (!items?.length) throw new Error('Add at least one item.');

  const { data: membership, error: membershipError } = await supabase
    .from('memberships')
    .select('organization_id, branch_id')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .limit(1)
    .single();
  if (membershipError) throw membershipError;

  const productIds = items.map((item) => item.productId);
  const { data: products, error: productError } = await supabase
    .from('products')
    .select('id,name,price')
    .in('id', productIds)
    .eq('is_active', true);
  if (productError) throw productError;

  const byId = new Map(products.map((product) => [product.id, product]));
  const normalized = items.map((item) => {
    const product = byId.get(item.productId);
    if (!product) throw new Error('One or more selected products are unavailable.');
    const quantity = Math.max(1, Number(item.quantity) || 1);
    return { product_id: product.id, product_name: product.name, unit_price: product.price, quantity, line_total: product.price * quantity };
  });

  const subtotal = normalized.reduce((sum, item) => sum + Number(item.line_total), 0);
  const { data: order, error: orderError } = await supabase
    .from('orders')
    .insert({
      organization_id: membership.organization_id,
      branch_id: membership.branch_id,
      user_id: user.id,
      customer_name: customerName.trim() || 'Walk-in customer',
      order_type: 'restaurant',
      status: paymentMethod === 'cash' ? 'completed' : 'pending',
      subtotal,
      discount_amount: 0,
      tax_amount: 0,
      total: subtotal,
      payment_status: paymentMethod === 'cash' ? 'paid' : 'pending',
      payment_method: paymentMethod,
    })
    .select('id,order_number')
    .single();
  if (orderError) throw orderError;

  const { error: itemsError } = await supabase.from('order_items').insert(
    normalized.map((item) => ({ ...item, order_id: order.id }))
  );
  if (itemsError) throw itemsError;

  if (paymentMethod === 'cash') {
    const { error: paymentError } = await supabase.from('payments').insert({
      organization_id: membership.organization_id,
      branch_id: membership.branch_id,
      order_id: order.id,
      received_by: user.id,
      method: 'cash',
      amount: subtotal,
      status: 'completed',
    });
    if (paymentError) throw paymentError;
  }

  return order;
}

export function formatMoney(value) {
  return `KSh ${Number(value || 0).toLocaleString('en-KE', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
