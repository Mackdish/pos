'use client';
import Link from 'next/link';
import { usePathname,useRouter } from 'next/navigation';
import { useEffect,useState } from 'react';
import { createClient } from '../lib/supabase/client';
const icons={dashboard:'⌂',order:'+',orders:'▤',kitchen:'◫',tables:'▦',inventory:'▥',shift:'▣',summary:'◔',admin:'◆',logout:'↪'};
const primary=[
 {href:'/orders',label:'Dashboard',icon:'dashboard'},
 {href:'/new-order',label:'New order',icon:'order'},
 {href:'/orders',label:'Orders',icon:'orders',match:'/orders/'},
 {href:'/kitchen',label:'Kitchen',icon:'kitchen'},
 {href:'/tables',label:'Tables',icon:'tables'},
 {href:'/inventory',label:'Inventory',icon:'inventory'},
 {href:'/shifts',label:'Cashier shifts',icon:'shift'},
 {href:'/daily-summary',label:'Daily summary',icon:'summary'},
];
function NavLink({item,active}){return <Link href={item.href} className={`flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition ${active?'bg-[#e8f3df] text-[#315f30]':'text-[#687467] hover:bg-[#f1f4ed] hover:text-[#263c2a]'}`}><span aria-hidden="true" className={`grid h-6 w-6 place-items-center text-base ${active?'text-[#4c843c]':'text-[#899688]'}`}>{icons[item.icon]}</span>{item.label}</Link>}
export default function AppShell({children}){const pathname=usePathname();const router=useRouter();const [superAdmin,setSuperAdmin]=useState(false);const isActive=item=>item.match?pathname===item.href||pathname.startsWith(item.match):pathname===item.href;
useEffect(()=>{let mounted=true;createClient().rpc('is_super_admin').then(({data})=>{if(mounted)setSuperAdmin(Boolean(data));});return()=>{mounted=false;};},[pathname]);
async function logout(){const supabase=createClient();await supabase.auth.signOut();router.replace('/');router.refresh()}
return <div className="min-h-screen bg-[#f7f8f5] text-[#203126] lg:grid lg:grid-cols-[244px_minmax(0,1fr)]"><header className="sticky top-0 z-20 flex h-16 items-center justify-between border-b border-[#e4e8e0] bg-white px-5 lg:hidden"><Link href="/orders" className="flex items-center gap-2.5"><span className="grid h-9 w-9 place-items-center rounded-xl bg-[#335f3b] text-sm font-black text-white">BH</span><span><b className="block text-sm">Bingo Hotel</b><span className="block text-[11px] text-[#768276]">Operations</span></span></Link><Link href="/new-order" className="rounded-lg bg-[#3f793d] px-3 py-2 text-xs font-bold text-white">+ New order</Link></header><aside className="hidden min-h-screen border-r border-[#e2e7df] bg-white p-4 lg:sticky lg:top-0 lg:flex lg:h-screen lg:flex-col"><Link href="/orders" className="mb-8 flex items-center gap-3 px-2 pt-2"><span className="grid h-10 w-10 place-items-center rounded-xl bg-[#335f3b] text-sm font-black text-white">BH</span><span><b className="block text-sm">Bingo Hotel</b><span className="block text-xs text-[#778276]">Hotel & Restaurant POS</span></span></Link><nav aria-label="Main navigation" className="space-y-1">{primary.map(item=><NavLink key={item.label} item={item} active={isActive(item}/>)}{superAdmin&&<NavLink item={{href:'/super-admin',label:'Super Admin',icon:'admin'}} active={pathname==='/super-admin'}/>}</nav><div className="mt-auto border-t border-[#e8ece5] pt-4"><button onClick={logout} className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left text-sm font-semibold text-[#a04943] hover:bg-[#fff4f2]"><span aria-hidden="true" className="grid h-6 w-6 place-items-center">{icons.logout}</span>Sign out</button></div></aside><div className="min-w-0">{children}</div></div>}
