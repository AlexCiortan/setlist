'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { render } = require('../src/app');

test('an empty wall says so', async () => {
  const fakeFetch = async () => ({ ok: true, json: async () => [] });
  assert.equal(await render(fakeFetch, 'http://api', 'w1'), 'No open slots on this wall.');
});
