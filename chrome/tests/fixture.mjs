#!/usr/bin/env node
// Build a throwaway LevelDB shaped like Chrome's sync store, so the tests
// never touch a real profile. Encodes the same protobuf layout tabgroups.mjs
// reads, plus records from other sync types — those are the ones a delete
// must leave alone.
//
// Usage: fixture.mjs <db-path>

import { ClassicLevel } from 'classic-level'

// --- minimal protobuf writer (mirror of the reader in lib/tabgroups.mjs) ---

function varint (n) {
  const bytes = []
  while (n > 127) { bytes.push((n & 0x7f) | 0x80); n = Math.floor(n / 128) }
  bytes.push(n)
  return Buffer.from(bytes)
}
const tag = (field, type) => varint((field << 3) | type)
const int = (field, value) => Buffer.concat([tag(field, 0), varint(value)])
const bytes = (field, buf) => {
  const b = Buffer.isBuffer(buf) ? buf : Buffer.from(buf, 'utf8')
  return Buffer.concat([tag(field, 2), varint(b.length), b])
}

// wrapper{1: version, 2: specifics}
const wrap = specifics => Buffer.concat([int(1, 1), bytes(2, specifics)])

const groupRecord = (guid, title, color) =>
  wrap(Buffer.concat([
    bytes(1, guid),
    bytes(4, Buffer.concat([bytes(2, title), int(3, color)]))
  ]))

const tabRecord = (guid, parent, url, title) =>
  wrap(Buffer.concat([
    bytes(1, guid),
    bytes(5, Buffer.concat([bytes(1, parent), bytes(3, url), bytes(4, title)]))
  ]))

// --- fixture data ----------------------------------------------------------

const GROUPS = [
  { guid: 'g0000001-0000-0000-0000-000000000001', title: 'rake SQ2-1365', color: 7 },
  { guid: 'g0000002-0000-0000-0000-000000000002', title: 'SQ2-1095', color: 1 },
  { guid: 'g0000003-0000-0000-0000-000000000003', title: 'NEXT', color: 4 },
  { guid: 'g0000004-0000-0000-0000-000000000004', title: 'Reviews', color: 1 }
]

const TABS = [
  { guid: 't0000001-0000-0000-0000-000000000001', parent: GROUPS[0].guid, url: 'https://example.com/a', title: 'a' },
  { guid: 't0000002-0000-0000-0000-000000000002', parent: GROUPS[0].guid, url: 'https://example.com/b', title: 'b' },
  { guid: 't0000003-0000-0000-0000-000000000003', parent: GROUPS[1].guid, url: 'https://example.com/c', title: 'c' },
  { guid: 't0000004-0000-0000-0000-000000000004', parent: GROUPS[3].guid, url: 'https://example.com/d', title: 'd' }
]

// Other sync types sharing the store. Deleting any of these would, on a real
// profile, cost preferences or passkeys.
const FOREIGN = [
  'preferences-dt-something',
  'preferences-md-something',
  'search_engines-dt-google',
  'sessions-dt-window1',
  'webauthn_credential-dt-passkey1',
  'saved_tab_group-GlobalMetadata'
]

const path = process.argv[2]
if (!path) {
  process.stderr.write('fixture: needs a db path\n')
  process.exit(1)
}

const db = new ClassicLevel(path)
await db.open()

const ops = []
for (const g of GROUPS) {
  ops.push({ type: 'put', key: `saved_tab_group-dt-${g.guid}`, value: groupRecord(g.guid, g.title, g.color) })
  // NEXT gets no metadata record — real stores have fewer -md- than -dt- keys,
  // and deleting an absent one must stay a no-op.
  if (g.title !== 'NEXT') {
    ops.push({ type: 'put', key: `saved_tab_group-md-${g.guid}`, value: Buffer.from('meta') })
  }
}
for (const t of TABS) {
  ops.push({ type: 'put', key: `saved_tab_group-dt-${t.guid}`, value: tabRecord(t.guid, t.parent, t.url, t.title) })
  ops.push({ type: 'put', key: `saved_tab_group-md-${t.guid}`, value: Buffer.from('meta') })
}
for (const key of FOREIGN) {
  ops.push({ type: 'put', key, value: Buffer.from('foreign') })
}

await db.batch(ops)
await db.close()
