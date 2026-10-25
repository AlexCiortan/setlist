'use strict';

// The two calls this front end makes to gym-api. The shapes are the API's,
// copied here by hand: there is no shared contract file yet.
async function openSlots(fetchImpl, apiUrl, wallId) {
  const res = await fetchImpl(`${apiUrl}/slots?wall=${encodeURIComponent(wallId)}`);
  if (!res.ok) throw new Error(`slots: ${res.status}`);
  return res.json();
}

async function bookSlot(fetchImpl, apiUrl, slotId, memberId, amount) {
  const res = await fetchImpl(`${apiUrl}/bookings`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ slotId, memberId, amount }),
  });
  if (res.status === 409) return { ok: false, reason: 'taken' };
  if (res.status === 402) return { ok: false, reason: 'payment' };
  return { ok: true, booking: await res.json() };
}

module.exports = { openSlots, bookSlot };
