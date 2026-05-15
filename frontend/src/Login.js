import React, { useState } from "react";
import { api, setSession } from "./api";

export default function Login({ onOk, onGoRegister, onGoAdmin }) {
  const [phone, setPhone] = useState("");
  const [password, setP] = useState("");
  const [err, setErr] = useState("");
  const [showPassword, setShowPassword] = useState(false);

  const submit = async () => {
    setErr("");
    try {
      const r = await api.login(phone, password);
      setSession(r.session);
      onOk();
    } catch (e) {
      setErr(e.message || "Login failed");
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

        <h2 className="text-xl font-semibold text-slate-900">Sign in</h2>
        <p className="text-sm text-slate-500 mt-1 mb-5">
          Use your account to access balance, transfers and notifications.
        </p>

        <div className="space-y-3">
          <input
            className="w-full rounded-xl border px-4 py-3 text-sm outline-none focus:ring-2 focus:ring-blue-500"
            placeholder="Phone number (digits only)"
            inputMode="numeric"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
          <div className="relative">
            <input
              className="w-full rounded-xl border px-4 py-3 pr-16 text-sm outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="Password"
              type={showPassword ? "text" : "password"}
              value={password}
              onChange={(e) => setP(e.target.value)}
            />
            <button
              type="button"
              onClick={() => setShowPassword((v) => !v)}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-xs font-semibold text-slate-600 hover:text-slate-900"
              aria-label={showPassword ? "Hide password" : "Show password"}
            >
              {showPassword ? "Hide" : "Show"}
            </button>
          </div>
        </div>

        <div className="mt-5 flex gap-3">
          <button
            onClick={submit}
            className="flex-1 rounded-xl bg-blue-600 px-4 py-3 text-sm font-semibold text-white hover:bg-blue-700"
          >
            Sign in
          </button>
          <button
            onClick={onGoRegister}
            className="flex-1 rounded-xl border px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-slate-50"
          >
            Create
          </button>
        </div>

        {err && (
          <div className="mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            {err}
          </div>
        )}

        <div className="mt-5 flex items-center justify-between text-xs text-slate-400">
          <span>© Banking Demo</span>
          {onGoAdmin && (
            <button onClick={onGoAdmin} className="text-amber-600 hover:text-amber-700 font-semibold">
              Admin
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
