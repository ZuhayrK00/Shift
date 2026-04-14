import Foundation
import Supabase

// Shared Supabase client. Use `supabase` everywhere in the app.
// The anon/publishable key is safe to embed — Supabase RLS enforces row-level
// access so users only ever see and mutate their own data.
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://dtzlfvuazdrgyyutjysm.supabase.co")!,
    supabaseKey: "sb_publishable_-rxave3eqYlrkEwuOisRFg_IjgA135r",
    options: .init(auth: .init(redirectToURL: URL(string: "com.zuhayrk.shift://callback")))
)
