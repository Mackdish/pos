import { createClient } from './supabase/client';

export async function getProducts() {
  const supabase = createClient();
  const { data, error } = await supabase.from('products').select('id, sku, name, description, price, category_id, is_active, categories(id,name)').eq('is_active', true).order('name');
  if (error) throw error;
  return data ?? [];
}

export async function getOrders({ limit = 100 } = {}) {
  const supabase = createClient();
  const { data, error } = await supabase.from('orders').select('id, order_number, customer_name, customer_phone, order_type, status, subtotal, discount_amount, tax_amount, total_amount, created_at, payment_status, branch_id, order_items(id,product_name,quantity,unit_price,line_total), payments(id,amount,method,status,reference,created_at)').order('created_at', { ascending: false }).limit(limit);
  if (error) throw error;
  return data ?? [];
}

export async function getOrder(id) {
  const supabase = createClient();
  const { data, error } = await supabase.from('orders').select('*, order_items(*, products(id,sku,name)), payments(id,amount,method,status,reference,phone_number,provider,created_at,confirmed_at)').eq('id', id).single();
  if (error) throw error;
  return data;
}

export async function createOrder({ customerName = 'Walk-in customer', customerPhone = '', items, paymentMethod = 'cash', orderType = 'counter', notes = '' }) {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('You must be signed in to create an order.');
  if (!items?.length) throw new Error('Add at least one item.');
  const { data: membership, error: membershipError } = await supabase.from('memberships').select('organization_id, branch_id').eq('user_id', user.id).eq('status', 'active').not('branch_id', 'is', null).order('created_at', { ascending: true }).limit(1).single();
  if (membershipError) throw new Error('No active branch membership is assigned to your account.');
  const { data, error } = await supabase.rpc('create_restaurant_order', { p_branch_id: membership.branch_id, p_customer_name: customerName, p_customer_phone: customerPhone, p_order_type: orderType, p_payment_method: paymentMethod, p_items: items.map((item) => ({ product_id: item.productId || item.id, quantity: Number(item.quantity) || 1 })), p_notes: notes });
  if (error) throw error;
  const order = data?.[0];
  if (!order) throw new Error('Order creation returned no result.');
  return { id: order.order_id, order_number: order.order_number, total_amount: order.total_amount };
}

export async function confirmOrderPayment(orderId, reference = '') {
  const supabase = createClient();
  const { data, error } = await supabase.rpc('confirm_order_payment', { p_order_id: orderId, p_reference: reference || null });
  if (error) throw error;
  return data;
}

export function formatMoney(value) {
  return `KSh ${Number(value || 0).toLocaleString('en-KE', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
