'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { createClient } from '../lib/supabase/client';

export default function SuperAdminPage() {
  const router = useRouter();
  const supabase = createClient();
  const [loading, setLoading] = useState(true);
  const [authorized, setAuthorized] = useState(false);
  const [organizations, setOrganizations] = useState([]);
  const [memberships, setMemberships] = useState([]);
  const [error, setError] = useState('');

  useEffect(() => {
    let active = true;
    async function load() {
      const { data: isAdmin, error: adminError } = await supabase.rpc('is_super_admin');
      if (adminError || !isAdmin) {
        if (active) {
          setError(adminError?.message || 'Super Admin access required.');
          setLoading(false);
        }
        return;
      }

      const [{ data: orgs, error: orgError }, { data: members, error: memberError }] = await Promise.all([
        supabase.from('organizations').select('id,name,slug,email,phone,city,county,country,is_active,created_at').order('created_at', { ascending: false }),
        supabase.from('memberships').select('id,organization_id,user_id,status,job_title,created_at').order('created_at', { ascending: false }),
      ]);

      if (!active) return;
      if (orgError || memberError) setError(orgError?.message || memberError?.message || 'Unable to load platform data.');
      setAuthorized(true);
      setOrganizations(orgs || []);
      setMemberships(members || []);
      setLoading(false);
    }
    load();
    return () => { active = false; };
  }, []);

  if (loading) return <main className="min-h-screen bg-[#f7f8f5] grid place-items-center text-sm text-[#718071]">Loading Super Admin Console…</main>;
  if (!authorized) return <main className="min-h-screen bg-[#f7f8f5] grid place-items-center px-5"><div className="w-full max-w-md rounded-2xl bg-white p-7 shadow-sm"><h1 className="text-xl font-bold">Access denied</h1><p className="mt-2 text-sm text-[#718071]">{error}</p><Link href="/" className="mt-5 inline-block rounded-xl bg-[#2f5b3c] px-4 py-3 text-sm font-bold text-white">Return to sign in</Link></div></main>;

  const activeOrganizations = organizations.filter(o => o.is_active).length;
  const activeUsers = memberships.filter(m => m.status === 'active').length;

  return (
    <main className="min-h-screen bg-[#f7f8f5] px-5 py-8 sm:px-8">
      <div className="mx-auto max-w-7xl">
        <header className="flex flex-col gap-4 border-b border-[#e2e7df] pb-6 sm:flex-row sm:items-end sm:justify-between">
          <div><p className="text-xs font-bold uppercase tracking-[.18em] text-[#6f8c61]">Platform control</p><h1 className="mt-1 text-3xl font-bold tracking-tight">Super Admin Console</h1><p className="mt-2 text-sm text-[#718071]">Manage organizations and monitor the entire POS platform.</p></div>
          <button onClick={async () => { await supabase.auth.signOut(); router.replace('/'); router.refresh(); }} className="rounded-xl border border-[#d9e1d4] bg-white px-4 py-2.5 text-sm font-semibold text-[#6b756b] hover:bg-[#f1f4ed]">Sign out</button>
        </header>

        {error && <div role="alert" className="mt-6 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}

        <section className="mt-7 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <Stat label="Total organizations" value={organizations.length} />
          <Stat label="Active organizations" value={activeOrganizations} />
          <Stat label="Active users" value={activeUsers} />
          <Stat label="Platform role" value="SUPER ADMIN" compact />
        </section>

        <section className="mt-8 overflow-hidden rounded-2xl border border-[#e2e7df] bg-white shadow-sm">
          <div className="border-b border-[#e8ece5] px-5 py-4"><h2 className="font-bold">Organizations</h2><p className="mt-1 text-xs text-[#7a8479]">All tenant organizations across the platform.</p></div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-left text-sm"><thead className="bg-[#f7f8f5] text-xs uppercase tracking-wide text-[#7a8479]"><tr><th className="px-5 py-3">Organization</th><th className="px-5 py-3">Location</th><th className="px-5 py-3">Users</th><th className="px-5 py-3">Status</th><th className="px-5 py-3">Created</th></tr></thead>
              <tbody>{organizations.map(org => { const count = memberships.filter(m => m.organization_id === org.id && m.status === 'active').length; return <tr key={org.id} className="border-t border-[#edf0eb]"><td className="px-5 py-4"><p className="font-semibold">{org.name}</p><p className="text-xs text-[#899288]">{org.email || org.slug}</p></td><td className="px-5 py-4 text-[#667066]">{[org.city, org.county].filter(Boolean).join(', ') || '—'}</td><td className="px-5 py-4 font-semibold">{count}</td><td className="px-5 py-4"><span className={`rounded-full px-2.5 py-1 text-xs font-bold ${org.is_active ? 'bg-[#e8f3df] text-[#356333]' : 'bg-[#f5e8e6] text-[#9a4942]'}`}>{org.is_active ? 'Active' : 'Suspended'}</span></td><td className="px-5 py-4 text-xs text-[#7b857b]">{new Date(org.created_at).toLocaleDateString()}</td></tr>; })}</tbody>
            </table>
          </div>
          {!organizations.length && <div className="px-5 py-10 text-center text-sm text-[#7a8479]">No organizations have been created yet.</div>}
        </section>
      </div>
    </main>
  );
}

function Stat({ label, value, compact }) { return <div className="rounded-2xl border border-[#e2e7df] bg-white p-5 shadow-sm"><p className="text-xs font-semibold uppercase tracking-wide text-[#7b857b]">{label}</p><p className={`mt-2 font-bold tracking-tight ${compact ? 'text-lg' : 'text-3xl'}`}>{value}</p></div>; }
