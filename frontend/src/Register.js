import React, { useState } from "react";
import { api } from "./api";

export default function Register({ onGoLogin }) {
  const [phone, setPhone] = useState("");
  const [username, setU] = useState("");
  const [password, setP] = useState("");
  const [msg, setMsg] = useState("");
  const [err, setErr] = useState("");
  const [loading, setLoading] = useState(false);

  const submit = async () => {
    if (loading) return;
    setLoading(true);
    setErr(""); setMsg("");
    try {
      const r = await api.register(phone, username, password);
      setMsg(`Account created. Your account number: ${r.account_number}. Please sign in.`);
    } catch (e) {
      setErr(e.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-50 flex items-center justify-center px-4">
      <div className="w-full max-w-md rounded-2xl border bg-white p-7 shadow-sm">
        <div className="flex items-center gap-3 mb-5">
          <div className="h-10 w-10 rounded-xl bg-blue-600 text-white grid place-items-center font-bold">B</div>
          <div>
            <div className="text-base font-semibold text-slate-900">Banking</div>
            <div className="text-xs text-slate-500">Postgres • Redis Session • WebSocket Notify</div>
          </div>
        </div>

        <h2 className="text-xl font-semibold text-slate-900">Create account</h2>
        <p className="text-sm text-slate-500 mt-1 mb-5">
          Register a new user to test transfers and realtime notifications.
        </p>

        <div className="space-y-3">
          <input
            className="w-full rounded-xl border px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="Phone number (digits only)"
            inputMode="numeric"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
          <input
            className="w-full rounded-xl border px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="Display name"
            value={username}
            onChange={(e) => setU(e.target.value)}
          />
          <input
            className="w-full rounded-xl border px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="Password (min 6 chars)"
            type="password"
            value={password}
            onChange={(e) => setP(e.target.value)}
          />
        </div>

        <div className="mt-5 flex gap-3">
          <button
            type="button"
            disabled={loading}
            onClick={submit}
            className="flex-1 rounded-xl bg-blue-600 px-4 py-3 text-sm font-semibold text-white hover:bg-blue-700 disabled:opacity-60"
          >
            {loading ? "Creating..." : "Create account"}
          </button>
          <button
            type="button"
            onClick={onGoLogin}
            className="flex-1 rounded-xl border px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-slate-50"
          >
            Back
          </button>
        </div>

        {msg && (
          <div className="mt-4 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">
            {msg}
          </div>
        )}
        {err && (
          <div className="mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            {err}
          </div>
        )}

        <div className="mt-5 text-xs text-slate-400">
          Security note: bcrypt has max 72 bytes password (lab constraint).
        </div>
      </div>
    </div>
  );
}
