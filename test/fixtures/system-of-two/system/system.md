# System spec: the climbing-gym booking system

The shape a system spec takes (Part 4 of the edition). This is the fixture's
example, so its content is a sketch; a real one is written by session zero.

## Components

- **gym-api** (`../api`): slots and bookings, and the call to the payments
  provider. Owner: the API team. Pipeline: its own (`ci/pipeline.yml`).
- **gym-web** (`../web`): the members' booking page. Owner: the web team.
  Pipeline: its own (`ci/pipeline.yml`).

## Crossings

- C1 gym-web to gym-api, `GET /slots`: contract `contracts/slots.md`, published
  by gym-api. Failure: the page shows the wall as unavailable.
- C2 gym-web to gym-api, `POST /bookings`: contract `contracts/bookings.md`,
  published by gym-api. Failure: 409 taken, 402 payment, shown to the member.
- C3 gym-api to the payments provider, `POST /charges`: the provider's contract.
  Failure: the booking is released and 402 returned.

## Bootstrap plan

1. api: directory `../api`, src `src`, tests `tests`, gate `node --test tests/*.test.js`, system_spec `../system/system.md`
2. web: directory `../web`, src `src`, tests `tests`, gate `node --test tests/*.test.js`, system_spec `../system/system.md`
