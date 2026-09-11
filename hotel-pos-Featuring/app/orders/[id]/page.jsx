'use client';
import Link from 'next/link';
import { use, useEffect, useState } from 'react';
import AppShell from '../../components/AppShell';
import { confirmOrderPayment, formatMoney, getOrder } from '../../lib/pos';

export default function OrderDetails({ params }) {
  const { id } = use(params);
  const [order, setOrder] = useState(null);
  const [reference, setReference] = useState('');
  const [loading, setLoading] = useState(true);
  const [approving, setApproving] = useState(false);
  const [error, setError] = useState('');

  async function load() {
    setLoading(true);
    try { setOrder(await getOrder(id)); } catch (e) { setError(e.message || 'Unable to load order.'); } finally { setLoading(false); }
  }
  useEffect(() => { load(); }, [id]);

  async function approve() {
    setApproving(true); setError('');
    try { await confirmOrderPayment(id, reference); await load(); } catch (e) { setError(e.message || 'Unable to verify payment.'); } finally { setApproving(false); }
  }

  if (loading) return <AppShell><main className="grid min-h-[calc(100vh-64px)] place-items-center text-sm text-[#748074]">Loading order…</main></AppShell>;
  if (!order) return <AppShell><main className="grid min-h-[calc(100vh-64px)] place-items-center"><div className="text-center"><p className="text-lg font-bold">Order not found</p><Link href="/orders" className="mt-3 inline-block text-sm font-bold text-[#3f7139]">Return to orders</Link></div></main></AppShell>;

  const payment = order.payments?.[0];
  const paid = order.payment_status === 'paid';
  return <AppShell><main className="px-5 py-8 sm:px-8 lg:px-10"><div className="mx-auto max-w-2xl"><Link href="/orders" className="text-sm font-bold text-[#4e7143]">← Today&apos;s orders</Link><article className="panel mt-5 overflow-hidden"><header className="border-b border-[#e7ebe4] bg-[#fbfcf8] p-6"><p className="eyebrow">Order record</p><div className="mt-2 flex flex-wrap items-center justify-between gap-3"><h1 className="text-3xl font-bold">#{order.order_number}</h1><span className={`rounded-full px-3 py-1.5 text-xs font-bold ${paid ? 'bg-[#e8f3e4] text-[#3d7137]' : 'bg-[#fff4db] text-[#97691b]'}`}>{paid ? '✓ PAYMENT PAID' : '◷ AWAITING PAYMENT'}</span></div><p className="mt-2 text-sm text-[#748074]">Recorded {new Date(order.created_at).toLocaleString('en-KE')}</p></header><div className="p-6"><div className="grid gap-5 border-b border-[#e7ebe4] pb-6 sm:grid-cols-2"><Info label="Customer" value={order.customer_name || 'Walk-in customer'} /><Info label="Payment method" value={payment?.method || '—'} /><Info label="Order status" value={order.status} /><Info label="Payment status" value={order.payment_status} /></div><h2 className="mt-6 font-bold">Items ordered</h2><div className="mt-3 divide-y divide-[#edf0eb]">{(order.order_items || []).map((item) => <div key={item.id} className="flex items-center justify-between py-3"><div><b>{item.product_name}</b><p className="text-sm text-[#748074]">{formatMoney(item.unit_price)} × {item.quantity}</p></div><b>{formatMoney(item.line_total)}</b></div>)}</div><div className="mt-4 flex justify-between border-t-2 border-[#203126] pt-4"><span className="text-lg font-bold">Total</span><span className="text-2xl font-bold">{formatMoney(order.total_amount)}</span></div>{!paid && payment?.method === 'mpesa' ? <div className="mt-7 rounded-2xl bg-[#fff8e8] p-4"><b className="text-[#7f5d19]">Verify the M-Pesa confirmation</b><p className="mt-1 text-sm leading-5 text-[#806d40]">Only approve after checking the customer&apos;s payment notification or provider reference.</p><input value={reference} onChange={e => setReference(e.target.value)} placeholder="M-Pesa transaction code (optional)" className="mt-4 w-full rounded-xl border border-[#ead9aa] bg-white px-3 py-3 text-sm outline-none" /><button disabled={approving} onClick={approve} className="mt-3 w-full rounded-xl bg-[#2f5b3c] py-3.5 font-bold text-white transition hover:bg-[#234b30] disabled:opacity-60">{approving ? 'Verifying…' : 'Confirm payment'}</button></div> : paid ? <div className="mt-7 rounded-2xl bg-[#edf5e9] p-4 text-sm"><b className="text-[#3d7137]">✓ Payment approved</b><p className="mt-1 text-[#597252]">{payment?.reference ? `Reference: ${payment.reference}` : 'Payment confirmed successfully.'}</p></div> : null}{error && <div role="alert" className="mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}<section className="mt-7 border-t border-[#e7ebe4] pt-5"><h2 className="font-bold">Activity</h2><div className="mt-4 space-y-4 border-l border-[#d9e3d5] pl-4 text-sm"><p><b className="block">{new Date(order.created_at).toLocaleTimeString('en-KE', { hour: '2-digit', minute: '2-digit' })} · Order created</b><span className="text-[#758075]">Customer: {order.customer_name || 'Walk-in customer'}</span></p>{paid && payment?.confirmed_at && <p><b className="block">{new Date(payment.confirmed_at).toLocaleTimeString('en-KE', { hour: '2-digit', minute: '2-digit' })} · Payment verified</b><span className="text-[#758075]">Payment status changed to paid.</span></p>}</div></section></div></article></div></main></AppShell>;
}
function Info({ label, value }) { return <div><p className="text-xs font-bold uppercase tracking-wider text-[#7d897c]">{label}</p><p className="mt-1 font-bold capitalize">{value}</p></div>; }
