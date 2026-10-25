'use strict';

// A slot is one wall for one hour. The store is in memory in this sketch.
const slots = new Map();

function listOpen(wallId) {
  return [...slots.values()].filter((s) => s.wallId === wallId && !s.bookedBy);
}

function book(slotId, memberId) {
  const slot = slots.get(slotId);
  if (!slot) return { ok: false, reason: 'no such slot' };
  if (slot.bookedBy) return { ok: false, reason: 'already booked' };
  slot.bookedBy = memberId;
  return { ok: true, slot };
}

function add(slot) {
  slots.set(slot.id, { ...slot, bookedBy: null });
}

module.exports = { listOpen, book, add };
