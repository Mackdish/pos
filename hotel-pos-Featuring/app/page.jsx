'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from './lib/supabase/client';

export default function LoginPage() {
  const router = useRouter();
  const supabase = createClient();
  const [mode, setMode] = useState('signin');
  const [next, setNext] = useState('/orders');
  const [form, setForm] = useState({ firstName: '', lastName: '', phone: '', email: '', password: '', confirmPassword: '' });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  useEffect(() => {
    const value = new URLSearchParams(window.location.search).get('next');
    if (value?.startsWith('/')) setNext(value);
  }, []);

  function switchMode(value) {
    setMode(value); setError(''); setMessage('');
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setError(''); setMessage(''); setLoading(true);
    const email = form.email.trim().toLowerCase();

    if (mode === 'signup') {
      if (form.password.length < 8) { setError('Password must be at least 8 characters.'); setLoading(false); return; }
      if (form.password !== form.confirmPassword) { setError('Passwords do not match.'); setLoading(false); return; }
      const { data, error: signUpError } = await supabase.auth.signUp({
        email,
        password: form.password,
        options: { data: { first_name: form.firstName.trim(), last_name: form.lastName.trim(), phone: form.phone.trim() } },
      });
      if (signUpError) { setError(signUpError.message || 'Unable to create your account.'); setLoading(false); return; }
      if (data.session) {
        const { data: isSuperAdmin } = await supabase.rpc('is_super_admin');
        router.replace(isSuperAdmin ? '/super-admin' : '/setup');
        router.refresh();
        return;
      }
      setMessage('Account created. Check your email to confirm your account, then sign in.');
      setMode('signin');
      setForm(prev => ({ ...prev, password: '', confirmPassword: '' }));
      setLoading(false);
      return;
    }

    const { error: signInError } = await supabase.auth.signInWithPassword({ email, password: form.password });
    if (signInError) { setError(signInError.message || 'Unable to sign in. Check your credentials.'); setLoading(false); return; }
    const { data: isSuperAdmin } = await supabase.rpc('is_super_admin');
    router.replace(isSuperAdmin ? '/super-admin' : (next.startsWith('/') ? next : '/orders'));
    router.refresh();
  }

  const inputClass = 'w-full rounded-xl border border-[#d9e1d4] bg-white px-4 py-3.5 outline-none transition focus:border-[#557c45] focus:ring-2 focus:ring-[#557c45]/15';

  return (
    <main className="min-h-screen bg-[#e8eddd] px-5 py-8 text-[#203126] sm:grid sm:place-items-center">
      <section className="mx-auto w-full max-w-[460px] rounded-[28px] bg-[#fbfcf8] px-7 py-9 shadow-[0_18px_55px_rgba(43,65,37,.14)] sm:px-10">
        <div className="mb-8 flex items-center gap-3"><div className="grid h-11 w-11 place-items-center rounded-2xl bg-[#2f5b3c] text-xl text-white">POS</div><div><p className="text-xs font-bold uppercase tracking-[.17em] text-[#739065]">Bingo Hotel</p><p className="text-sm text-[#6e776e]">Hotel & Restaurant POS</p></div></div>
        <div className="mb-7 grid grid-cols-2 rounded-xl bg-[#edf1e9] p-1"><button type="button" onClick={() => switchMode('signin')} className={`rounded-lg py-2.5 text-sm font-bold ${mode === 'signin' ? 'bg-white text-[#315f30] shadow-sm' : 'text-[#748073]'}`}>Sign in</button><button type="button" onClick={() => switchMode('signup')} className={`rounded-lg py-2.5 text-sm font-bold ${mode === 'signup' ? 'bg-white text-[#315f30] shadow-sm' : 'text-[#748073]'}`}>Create account</button></div>
        <p className="mb-2 text-xs font-bold uppercase tracking-[.18em] text-[#759168]">{mode === 'signup' ? 'New account' : 'Secure sign in'}</p>
        <h1 className="text-3xl font-bold tracking-tight">{mode === 'signup' ? 'Create your account' : 'Welcome back'}</h1>
        <p className="mt-3 text-[15px] leading-6 text-[#6c766d]">{mode === 'signup' ? 'Create an account to get started with the hotel and restaurant POS.' : 'Sign in with your account to access the point-of-sale system.'}</p>
        <form onSubmit={handleSubmit} className="mt-8 space-y-4">
          {mode === 'signup' && <div className="grid gap-4 sm:grid-cols-2"><label className="block"><span className="mb-2 block text-sm font-semibold text-[#4d5b50]">First name</span><input className={inputClass} value={form.firstName} onChange={e => setForm({ ...form, firstName: e.target.value })} autoComplete="given-name" required /></label><label className="block"><span className="mb-2 block text-sm font-semibold text-[#4d5b50]">Last name</span><input className={inputClass} value={form.lastName} onChange={e => setForm({ ...form, lastName: e.target.value })} autoComplete="family-name" required /></label></div>}
          <label className="block"><span className="mb-2 block text-sm font-semibold text-[#4d5b50]">Email address</span><input type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} autoComplete="email" required className={inputClass} placeholder="you@example.com" /></label>
          {mode === 'signup' && <label className="block"><span className="mb-2 block text-sm font-semibold text-[#4d5b50]">Phone number <span className="font-normal text-[#899288]">(optional)</span></span><input type="tel" value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} autoComplete="tel" className={inputClass} placeholder="07xx xxx xxx" /></label>}
          <label className="block"><span className="mb-2 block text-sm font-semibold text-[#4d5b50]">Password</span><input type="password" value={form.password} onChange={e => setForm({ ...form, password: e.target.value })} autoComplete={mode === 'signup' ? 'new-password' : 'current-password'} required className={inputClass} placeholder="••••••••" /></label>
          {mode === 'signup' && <label className="block"><span className="mb-2 block text-sm font-semibold text-[#4d5b50]">Confirm password</span><input type="password" value={form.confirmPassword} onChange={e => setForm({ ...form, confirmPassword: e.target.value })} autoComplete="new-password" required className={inputClass} placeholder="••••••••" /></label>}
          {error && <div role="alert" className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}
          {message && <div role="status" className="rounded-xl border border-[#cfe2c7] bg-[#eef7e9] px-4 py-3 text-sm text-[#356333]">{message}</div>}
          <button type="submit" disabled={loading} className="flex w-full items-center justify-center gap-3 rounded-xl bg-[#2f5b3c] px-5 py-4 font-bold text-white shadow-lg shadow-[#2f5b3c]/20 transition hover:bg-[#234b30] disabled:cursor-not-allowed disabled:opacity-60">{loading ? (mode === 'signup' ? 'Creating account…' : 'Signing in…') : (mode === 'signup' ? 'Create account' : 'Sign in')}{!loading && <span>→</span>}</button>
        </form>
        <p className="mt-6 text-center text-xs leading-5 text-[#8b948b]">Access is controlled by organization membership and assigned permissions.</p>
      </section>
    </main>
  );
}
