import Foundation
import Supabase

private let shiftBackendURL: URL = {
    #if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
    if StoreCaptureConfiguration.enabled { return URL(string: "http://127.0.0.1:1")! }
    #endif
    return URL(string: "https://dtzlfvuazdrgyyutjysm.supabase.co")!
}()

// Shared Supabase client. Use `supabase` everywhere in the app.
// The anon/publishable key is safe to embed — Supabase RLS enforces row-level
// access so users only ever see and mutate their own data.
let supabase = SupabaseClient(
    supabaseURL: shiftBackendURL,
    supabaseKey: "sb_publishable_-rxave3eqYlrkEwuOisRFg_IjgA135r",
    options: .init(auth: .init(
        redirectToURL: URL(string: "com.zuhayrk.shift://callback"),
        emitLocalSessionAsInitialSession: true
    ))
)
