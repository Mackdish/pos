'use client';

import { useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { createClient } from './lib/supabase/client';

export default function LoginPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const next = searchParams.get('next') || '/orders';
  const supabase = createClient();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  async function handleSubmit(event) {
    event.preventDefault();
    setError('');
    setLoading(true);
    const { error: signInError } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (signInError) {
      setError(signInError.message || 'Unable to sign in. Check your credentials.');
      setLoading(false);
      return;
    }
    router.replace(next.startsWith('/') ? next : '/orders');
    router.refresh();
  }

  return (
    <main className="min-h-screen bg-[#e8eddd] px-5 py-8 text-[#203126] sm:grid sm:place-items-center">
      <section className="mx-auto w-full max-w-[460px] rounded-[28px] bg-[#fbfcf8] px-7 py-9 shadow-[0_18px_55px_rgba(43,65,37,.14)] sm:px-10">
        <div className="mb-10 flex items-center gap-3">
          <div className="grid h-11 w-11 place-items-center rounded-2xl bg-[#2f5b3c] text-xl text-white">POS</div>
          <div><p className="text-xs font-bold uppercase tracking-[.17em] text-[#739065]">Bingo Hotel</p><p className="text-sm text-[#6e776e]">Hotel & Restaurant POS</p></div>
        </div>
        <p className="mb-2 text-xs font-bold uppercase tracking-[.18em] text-[#759168]">Secure sign in</p>
        <h1 className="text-3xl font-bold tracking-tight">Welcome back</h1>
        <p className="mt-3 text-[15px] leading-6 text-[#6c766d]">Sign in with your staff account to access the point-of-sale system.</p>
        <form onSubmit={handleSubmit} className="mt-8 space-y-4">
          <label className="block"><span className="mb-2 block text-sm font-semibold text-[#4d5b50]">Email address</span><input type="email" value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" required className="w-full rounded-xl border border-[#d9e1d4] bg-white px-4 py-3.5 outline-none transition focus:border-[#557c45] focus:ring-2 focus:ring-[#557c45]/15" placeholder="staff@example.com" /></label>
          <label className="block"><span className="mb-2 block text-sm font-semibold text-[#4d5b50]">Password</span><input type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="current-password" required className="w-full rounded-xl border border-[#d9e1d4] bg-white px-4 py-3.5 outline-none transition focus:border-[#557c45] focus:ring-2 focus:ring-[#557c45]/15" placeholder="••••••••" /></label>
          {error && <div role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}
          <button type="submit" disabled={loading} className="flex w-full items-center justify-center gap-3 rounded-xl bg-[#2f5b3c] px-5 py-4 font-bold text-white shadow-lg shadow-[#2f5b3c]/20 transition hover:bg-[#234b30] disabled:cursor-not-allowed disabled:opacity-60">{loading ? 'Signing in…' : 'Sign in'}{!loading && <span>→</span>}</button>
        </form>
        <p className="mt-6 text-center text-xs leading-5 text-[#8b948b]">Access is controlled by your organization membership and assigned permissions.</p>
      </section>
    </main>
  );
}
