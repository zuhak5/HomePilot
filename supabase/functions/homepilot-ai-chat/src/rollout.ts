export async function isAssignedToRollout(
  userId: string,
  salt: string,
  percentage: number,
): Promise<boolean> {
  if (percentage <= 0) return false;
  if (percentage >= 100) return true;
  const bytes = new TextEncoder().encode(`${salt}:${userId}`);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  const value = ((digest[0] ?? 0) << 24) | ((digest[1] ?? 0) << 16) |
    ((digest[2] ?? 0) << 8) | (digest[3] ?? 0);
  return (value >>> 0) % 100 < percentage;
}
