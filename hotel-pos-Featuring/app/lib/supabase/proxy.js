import { createServerClient } from '@supabase/ssr';
import { NextResponse } from 'next/server';

export async function updateSession(request) {
  const pathname = request.nextUrl.pathname;
  const isPublic = pathname === '/' || pathname.startsWith('/auth');

  // Public routes do not need a Supabase session check. This is important on
  // Cloudflare because missing runtime variables must not turn the login page
  // into a Worker 500 error.
  if (isPublic) {
    return NextResponse.next({ request });
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseKey =
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Fail safely when Supabase is not configured at runtime.
  if (!supabaseUrl || !supabaseKey) {
    const url = request.nextUrl.clone();
    url.pathname = '/';
    url.searchParams.set('next', pathname);
    return NextResponse.redirect(url);
  }

  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(supabaseUrl, supabaseKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        supabaseResponse = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) =>
          supabaseResponse.cookies.set(name, value, options)
        );
      },
    },
  });

  try {
    const {
      data: { claims },
    } = await supabase.auth.getClaims();

    if (!claims?.sub) {
      const url = request.nextUrl.clone();
      url.pathname = '/';
      url.searchParams.set('next', pathname);
      return NextResponse.redirect(url);
    }

    return supabaseResponse;
  } catch (error) {
    console.error('Supabase session check failed:', error);
    const url = request.nextUrl.clone();
    url.pathname = '/';
    url.searchParams.set('next', pathname);
    return NextResponse.redirect(url);
  }
}
