'use strict';

const client = require('./api-client');

// Renders a wall's open slots as text lines; a real page would render HTML.
async function render(fetchImpl, apiUrl, wallId) {
  const open = await client.openSlots(fetchImpl, apiUrl, wallId);
  if (open.length === 0) return 'No open slots on this wall.';
  return open.map((s) => `${s.start}  ${s.id}`).join('\n');
}

module.exports = { render };
