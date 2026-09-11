'use client';

import { useEffect, useMemo, useState } from 'react';
import AppShell from '../components/AppShell';
import { createClient } from '../lib/supabase/client';
import { formatMoney } from '../lib/pos';

export default function InventoryPage() {
  const supabase = createClient();
  const [items, setItems] = useState([]);
  const [branches, setBranches] = useState([]);
  const [branchId, setBranchId] = useState('');
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ name: '', sku: '', unit: 'unit', reorderLevel: '', costPrice: '', quantity: '' });
  const [saving, setSaving] = useState(false);

  async function load() {
    setLoading(true); setError('');
    const { data: memberships, error: membershipError } = await supabase.from('memberships').select('branch_id, branches(id,name,code)').eq('status','active').not('branch_id','is',null);
    if (membershipError) { setError(membershipError.message); setLoading(false); return; }
    const uniqueBranches = (memberships || []).map(m => m.branches).filter(Boolean);
    setBranches(uniqueBranches);
    const selected = branchId || uniqueBranches[0]?.id || '';
    if (!branchId && selected) setBranchId(selected);
    const { data, error: itemError } = await supabase.from('inventory_items').select('id,name,sku,unit,reorder_level,cost_price,is_active,stock_levels!inner(branch_id,quantity)').eq('is_active',true).eq('stock_levels.branch_id',selected).order('name');
    if (itemError) setError(itemError.message); else setItems(data || []);
    setLoading(false);
  }
  useEffect(() => { load(); }, [branchId]);

  const shown = useMemo(() => items.filter(i => `${i.name} ${i.sku || ''}`.toLowerCase().includes(search.toLowerCase())), [items, search]);
  const low = shown.filter(i => Number(i.stock_levels?.[0]?.quantity || 0) <= Number(i.reorder_level || 0));

  async function createItem(e) {
    e.preventDefault(); setSaving(true); setError('');
    try {
      const { data: membership } = await supabase.from('memberships').select('organization_id').eq('branch_id',branchId).eq('status','active').limit(1).single();
      if (!membership) throw new Error('No active branch membership found.');
      const { data: item, error: itemError } = await supabase.from('inventory_items').insert({ organization_id: membership.organization_id, name: form.name.trim(), sku: form.sku.trim() || null, unit: form.unit.trim() || 'unit', reorder_level: Number(form.reorderLevel) || 0, cost_price: Number(form.costPrice) || 0 }).select('id').single();
      if (itemError) throw itemError;
      if (Number(form.quantity) > 0) {
        const { error: movementError } = await supabase.rpc('record_stock_movement', { p_branch_id: branchId, p_inventory_item_id: item.id, p_movement_type: 'opening', p_quantity: Number(form.quantity), p_unit_cost: Number(form.costPrice) || 0, p_notes: 'Opening stock' });
        if (movementError) throw movementError;
      }
      setForm({ name:'', sku:'', unit:'unit', reorderLevel:'', costPrice:'', quantity:'' }); setShowForm(false); await load();
    } catch (e) { setError(e.message || 'Unable to create inventory item.'); }
    finally { setSaving(false); }
  }

  async function receive(item) {
    const quantity = Number(window.prompt(`Quantity to receive for ${item.name}:`, '1'));
    if (!Number.isFinite(quantity) || quantity <= 0) return;
    const { error } = await supabase.rpc('record_stock_movement', { p_branch_id: branchId, p_inventory_item_id: item.id, p_movement_type: 'receive', p_quantity: quantity, p_unit_cost: Number(item.cost_price || 0), p_notes: 'Stock received' });
    if (error) setError(error.message); else load();
  }

  return <AppShell><main className="mx-auto max-w-7xl px-5 py-8 sm:px-8 lg:px-10"><div className="flex flex-wrap items-end justify-between gap-4"><div><p className="eyebrow">Back office</p><h1 className="mt-1 text-3xl font-bold tracking-tight">Inventory</h1><p className="mt-2 text-sm text-[#748074]">Track stock by branch, receive goods and catch low-stock items before service is affected.</p></div><button onClick={() => setShowForm(!showForm)} className="rounded-xl bg-[#3c763a] px-4 py-3 text-sm font-bold text-white">{showForm ? 'Close' : '+ Add stock item'}</button></div>{error && <div role="alert" className="mt-5 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}{showForm && <form onSubmit={createItem} className="panel mt-6 grid gap-4 p-5 sm:grid-cols-2 lg:grid-cols-3"><Field label="Item name" value={form.name} onChange={v=>setForm({...form,name:v})} required/><Field label="SKU" value={form.sku} onChange={v=>setForm({...form,sku:v})}/><Field label="Unit" value={form.unit} onChange={v=>setForm({...form,unit:v})}/><Field label="Reorder level" type="number" value={form.reorderLevel} onChange={v=>setForm({...form,reorderLevel:v})}/><Field label="Cost price" type="number" value={form.costPrice} onChange={v=>setForm({...form,costPrice:v})}/><Field label="Opening quantity" type="number" value={form.quantity} onChange={v=>setForm({...form,quantity:v})}/><button disabled={saving || !branchId} className="rounded-xl bg-[#2f5b3c] px-4 py-3 font-bold text-white disabled:opacity-50 sm:col-span-2 lg:col-span-3">{saving ? 'Saving…' : 'Save stock item'}</button></form>}<section className="mt-8 grid gap-4 sm:grid-cols-3"><Metric label="Stock items" value={String(shown.length)}/><Metric label="Low stock" value={String(low.length)} warn/><Metric label="Estimated stock value" value={formatMoney(shown.reduce((s,i)=>s + Number(i.stock_levels?.[0]?.quantity||0)*Number(i.cost_price||0),0))}/></section><section className="panel mt-6 overflow-hidden"><div className="flex flex-wrap items-center justify-between gap-3 border-b border-[#e7ebe4] p-5"><div className="flex gap-2"><select value={branchId} onChange={e=>setBranchId(e.target.value)} className="rounded-xl border border-[#dfe6da] bg-white px-3 py-2.5 text-sm">{branches.map(b=><option key={b.id} value={b.id}>{b.name} ({b.code})</option>)}</select><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search stock" className="rounded-xl border border-[#dfe6da] px-3 py-2.5 text-sm"/></div></div>{loading ? <div className="p-12 text-center text-sm text-[#758075]">Loading inventory…</div> : <div className="overflow-x-auto"><div className="min-w-[720px]"><div className="grid grid-cols-[1.5fr_120px_120px_130px_110px] gap-4 bg-[#fbfcfa] px-5 py-3 text-[11px] font-bold uppercase tracking-wider text-[#7c887b]"><span>Item</span><span>SKU</span><span>On hand</span><span>Value</span><span/></div>{shown.map(item=>{const qty=Number(item.stock_levels?.[0]?.quantity||0);const isLow=qty<=Number(item.reorder_level||0);return <div key={item.id} className="grid grid-cols-[1.5fr_120px_120px_130px_110px] items-center gap-4 border-t border-[#eef1ed] px-5 py-4 text-sm"><div><b>{item.name}</b><span className="ml-2 rounded-full bg-[#eef2eb] px-2 py-1 text-xs">{item.unit}</span>{isLow&&<span className="ml-2 rounded-full bg-[#fff1df] px-2 py-1 text-xs font-bold text-[#97671c]">Low</span>}</div><span>{item.sku || '—'}</span><b>{qty.toLocaleString()} {item.unit}</b><span>{formatMoney(qty*Number(item.cost_price||0))}</span><button onClick={()=>receive(item)} className="rounded-lg border border-[#d7e1d2] px-3 py-2 text-xs font-bold">Receive</button></div>})}{!shown.length&&<div className="p-12 text-center text-sm text-[#758075]">No inventory items found.</div>}</div></div>}</section></main></AppShell>;
}
function Field({label,value,onChange,type='text',required}){return <label className="block"><span className="mb-2 block text-sm font-semibold">{label}</span><input required={required} type={type} value={value} onChange={e=>onChange(e.target.value)} className="w-full rounded-xl border border-[#d9e1d4] px-4 py-3 outline-none focus:border-[#557c45]"/></label>}
function Metric({label,value,warn}){return <div className={`panel p-5 ${warn?'border-[#efdca6] bg-[#fffdf7]':''}`}><p className="text-sm text-[#748074]">{label}</p><p className="mt-2 text-2xl font-bold">{value}</p></div>}
