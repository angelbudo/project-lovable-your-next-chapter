import { supabase } from "@/integrations/supabase/client";

export const USERNAME_REGEX = /^[a-z][a-z0-9_]{2,19}$/;

export function normalizeUsername(raw: string): string {
  return raw.trim().toLowerCase();
}

export function validateUsernameFormat(raw: string): string | null {
  const u = normalizeUsername(raw);
  if (!u) return "El nom d'usuari no pot estar buit";
  if (u.length < 3) return "Mínim 3 caràcters";
  if (u.length > 20) return "Màxim 20 caràcters";
  if (!USERNAME_REGEX.test(u))
    return "Només lletres minúscules, xifres i _ (ha de començar per lletra)";
  return null;
}

export async function isUsernameAvailable(raw: string): Promise<boolean> {
  const u = normalizeUsername(raw);
  if (validateUsernameFormat(u)) return false;
  const { data, error } = await supabase.rpc("is_username_available", { p_username: u });
  if (error) return false;
  return Boolean(data);
}

const ERR_MAP: Record<string, string> = {
  invalid_username: "Nom d'usuari no vàlid",
  invalid_format: "Format incorrecte",
  reserved_username: "Aquest nom està reservat",
  username_taken: "Aquest nom d'usuari ja està agafat",
  not_authenticated: "Has d'iniciar sessió",
  profile_not_found: "Perfil no trobat",
};

export async function setUsername(raw: string): Promise<void> {
  const u = normalizeUsername(raw);
  const formatErr = validateUsernameFormat(u);
  if (formatErr) throw new Error(formatErr);
  const { error } = await supabase.rpc("set_username", { p_username: u });
  if (error) {
    const msg = (error.message || "").toLowerCase();
    for (const [k, v] of Object.entries(ERR_MAP)) {
      if (msg.includes(k)) throw new Error(v);
    }
    throw new Error(error.message);
  }
}