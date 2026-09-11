'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

const employees = [
  { name: 'Jane W.', role: 'Receptionist', initials: 'JW', color: 'bg-[#dce8bd] text-[#45602c]' },
  { name: 'Brian K.', role: 'Receptionist', initials: 'BK', color: 'bg-[#d9e5f5] text-[#315782]' },
  { name: 'Mary A.', role: 'Manager', initials: 'MA', color: 'bg-[#f4dfc7] text-[#8a5a21]' },
];

export default function EmployeeSelect() {
  const [employee, setEmployee] = useState(employees[0]);
  const router = useRouter();
  function continueToApp() { localStorage.setItem('currentEmployee', employee.name); router.push('/orders'); }
  return <main className="min-h-screen bg-[#e8eddd] px-5 py-8 text-[#203126] sm:grid sm:place-items-center">
    <section className="mx-auto w-full max-w-[460px] rounded-[28px] bg-[#fbfcf8] px-7 py-9 shadow-[0_18px_55px_rgba(43,65,37,.14)] sm:px-10">
      <div className="mb-10 flex items-center gap-3"><div className="grid h-11 w-11 place-items-center rounded-2xl bg-[#2f5b3c] text-xl text-white">LOGO</div><div><p className="text-xs font-bold uppercase tracking-[.17em] text-[#739065]">Bingo Hotel</p><p className="text-sm text-[#6e776e]">Food order book</p></div></div>
      <p className="mb-2 text-xs font-bold uppercase tracking-[.18em] text-[#759168]">Welcome back</p><h1 className="text-3xl font-bold tracking-tight">Who is recording<br />orders today?</h1><p className="mt-3 text-[15px] leading-6 text-[#6c766d]">Choose your name to start a new shift. Every order is attributed to you.</p>
      <div className="mt-8 space-y-3">{employees.map((person) => <button key={person.name} onClick={() => setEmployee(person)} className={`flex w-full items-center gap-4 rounded-2xl border p-4 text-left transition ${employee.name === person.name ? 'border-[#557c45] bg-[#f0f5e7] ring-1 ring-[#557c45]' : 'border-[#e2e7dc] bg-white hover:border-[#a8bb9a]'}`}><span className={`grid h-11 w-11 place-items-center rounded-full text-sm font-bold ${person.color}`}>{person.initials}</span><span className="flex-1"><span className="block font-bold">{person.name}</span><span className="text-sm text-[#7a837a]">{person.role}</span></span><span className={`h-5 w-5 rounded-full border-2 ${employee.name === person.name ? 'border-[#557c45] bg-[#557c45] shadow-[inset_0_0_0_3px_#f0f5e7]' : 'border-[#c6cec3]'}`} /></button>)}</div>
      <button onClick={continueToApp} className="mt-8 flex w-full items-center justify-center gap-3 rounded-xl bg-[#2f5b3c] px-5 py-4 font-bold text-white shadow-lg shadow-[#2f5b3c]/20 hover:bg-[#234b30]">Continue to orders <span>→</span></button>
      <p className="mt-5 text-center text-xs text-[#8b948b]">Your activity will be recorded for accountability.</p>
    </section>
  </main>;
}
