"use client";

import { useState, FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [message, setMessage] = useState("");

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setMessage("Working...");

    const { error } =
      mode === "signup"
        ? await supabase.auth.signUp({
            email,
            password,
            options: { data: { display_name: displayName } },
          })
        : await supabase.auth.signInWithPassword({ email, password });

    if (error) {
      setMessage(error.message);
    } else {
      router.push("/");
      router.refresh();
    }
  }

  return (
    <main className="p-8">
      <Link href="/" className="text-blue-400">← Back</Link>
      <h1 className="mt-4 text-3xl font-bold">
        {mode === "login" ? "Log in" : "Create account"}
      </h1>

      <form onSubmit={handleSubmit} className="mt-6 flex max-w-sm flex-col gap-4">
        {mode === "signup" && (
          <label className="flex flex-col gap-1">
            Display name (what your friends will see)
            <input
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              className="rounded bg-white p-2 text-black"
              required
            />
          </label>
        )}

        <label className="flex flex-col gap-1">
          Email
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="rounded bg-white p-2 text-black"
            required
          />
        </label>

        <label className="flex flex-col gap-1">
          Password (at least 6 characters)
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="rounded bg-white p-2 text-black"
            required
            minLength={6}
          />
        </label>

        <button type="submit" className="rounded bg-blue-600 px-4 py-2 text-white">
          {mode === "login" ? "Log in" : "Sign up"}
        </button>

        <button
          type="button"
          onClick={() => setMode(mode === "login" ? "signup" : "login")}
          className="text-sm text-blue-400"
        >
          {mode === "login"
            ? "No account? Create one"
            : "Already have an account? Log in"}
        </button>
      </form>

      {message && <p className="mt-6 text-red-400">{message}</p>}
    </main>
  );
}