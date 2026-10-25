'use strict';

const test = require('node:test');
const assert = require('node:assert');
const slots = require('../src/slots');

test('a booked slot is no longer open', () => {
  slots.add({ id: 's1', wallId: 'w1', start: '2026-11-01T10:00' });
  assert.equal(slots.listOpen('w1').length, 1);
  assert.equal(slots.book('s1', 'm1').ok, true);
  assert.equal(slots.listOpen('w1').length, 0);
  assert.equal(slots.book('s1', 'm2').reason, 'already booked');
});
