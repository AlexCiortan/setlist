'use strict';

const http = require('node:http');
const slots = require('./slots');
const payments = require('./payments');

// GET /slots?wall=<id>  -> 200 [{id, wallId, start}]
// POST /bookings {slotId, memberId, amount} -> 201 {slot, charge} | 409 | 402
function handler(deps) {
  return async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    if (req.method === 'GET' && url.pathname === '/slots') {
      res.writeHead(200, { 'content-type': 'application/json' });
      return res.end(JSON.stringify(slots.listOpen(url.searchParams.get('wall'))));
    }
    if (req.method === 'POST' && url.pathname === '/bookings') {
      let body = '';
      for await (const chunk of req) body += chunk;
      const { slotId, memberId, amount } = JSON.parse(body);
      const booked = slots.book(slotId, memberId);
      if (!booked.ok) { res.writeHead(409); return res.end(booked.reason); }
      const paid = await payments.charge(deps.fetch, deps.paymentsUrl, { slotId, amount });
      if (!paid.ok) { res.writeHead(402); return res.end('payment failed'); }
      res.writeHead(201, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ slot: booked.slot, charge: paid.charge }));
    }
    res.writeHead(404); res.end();
  };
}

module.exports = { handler, createServer: (deps) => http.createServer(handler(deps)) };
