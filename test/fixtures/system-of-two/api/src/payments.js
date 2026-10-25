'use strict';

// The payments provider is an outside service. Its base URL comes from the
// environment the deploy sets; the request shape is the provider's.
async function charge(fetchImpl, baseUrl, booking) {
  const res = await fetchImpl(`${baseUrl}/charges`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ amount: booking.amount, reference: booking.slotId }),
  });
  if (!res.ok) return { ok: false, status: res.status };
  return { ok: true, charge: await res.json() };
}

module.exports = { charge };
