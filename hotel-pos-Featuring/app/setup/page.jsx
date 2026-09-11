'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import AppShell from '../components/AppShell';
import { createClient } from '../lib/supabase/client';

export default function SetupPage() {
  const router = useRouter();
  const supabase = createClient();
  const [form, setForm] = useState({ name: '', branchName: 'Main Branch', branchCode: 'MAIN', email: '', phone: '' });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  async function submit(event) {
    event.preventDefault(); setLoading(true); setError('');
    const { error: setupError } = await supabase.rpc('create_organization_with_admin', { p_name: form.name, p_branch_name: form.branchName, p_branch_code: form.branchCode, p_email: form.email || null, p_phone: form.phone || null });
    if (setupError) { setError(setupError.message || 'Unable to create the organization.'); setLoading(false); return; }
    router.replace('/orders'); router.refresh();
  }

  return <AppShell><main className="min-h-screen bg-[#f7f8f5] px-5 py-10 sm:px-8"><div className="mx-auto max-w-2xl"><p className="eyebrow">Initial setup</p><h1 className="mt-1 text-3xl font-bold tracking-tight">Set up your business</h1><p className="mt-2 text-sm leading-6 text-[#718071]">Create the first organization and branch. Your account will become the administrator automatically.</p><form onSubmit={submit} className="panel mt-8 space-y-5 p-6"><Field label="Business / hotel name" value={form.name} onChange={v => setForm({ ...form, name: v })} placeholder="Bingo Hotel" required /><div className="grid gap-5 sm:grid-cols-2"><Field label="Branch name" value={form.branchName} onChange={v => setForm({ ...form, branchName: v })} placeholder="Main Branch" required /><Field label="Branch code" value={form.branchCode} onChange={v => setForm({ ...form, branchCode: v.toUpperCase() })} placeholder="MAIN" required /></div><div className="grid gap-5 sm:grid-cols-2"><Field label="Business email" type="email" value={form.email} onChange={v => setForm({ ...form, email: v })} placeholder="info@example.com" /><Field label="Business phone" value={form.phone} onChange={v => setForm({ ...form, phone: v })} placeholder="07xx xxx xxx" /></div>{error && <div role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}<button disabled={loading} className="w-full rounded-xl bg-[#2f5b3c] py-3.5 font-bold text-white transition hover:bg-[#234b30] disabled:opacity-60">{loading ? 'Creating organization…' : 'Create organization →'}</button></form></div></main></AppShell>;
}

function Field({ label, value, onChange, type = 'text', placeholder, required }) { return <label className="block"><span className="mb-2 block text-sm font-semibold text-[#4d5b50]">{label}</span><input type={type} value={value} onChange={e => onChange(e.target.value)} placeholder={placeholder} required={required} className="w-full rounded-xl border border-[#d9e1d4] bg-white px-4 py-3.5 outline-none transition focus:border-[#557c45] focus:ring-2 focus:ring-[#557c45]/15" /></label>; }
