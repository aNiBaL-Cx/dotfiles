#!/usr/bin/env node
// LevelDB half of chrome-tab-groups. The bash script owns the CLI, safety
// gates and presentation; this owns reading and writing Chrome's store.
//
// Chrome keeps saved tab groups in the profile's sync store:
//   <profile>/Sync Data/LevelDB
// under keys "saved_tab_group-dt-<guid>" (the record) and
// "saved_tab_group-md-<guid>" (sync metadata). Groups and their tabs are
// separate records at the same level — a tab points at its group by guid.
//
// That store ALSO holds preferences, search_engines, sessions and
// webauthn_credential records. Every write here is scoped to saved_tab_group
// keys; nothing else may be touched. See tests/chrome-tab-groups.test.sh.
//
// Usage:
//   tabgroups.mjs list   --db <path> [--filter <s>] [--regex] [--all]
//   tabgroups.mjs delete --db <path> --guid <g> [--guid <g>...]
//   tabgroups.mjs update --db <path> --file <tsv>
//
// list   -> TSV on stdout: guid \t tabcount \t color \t title
// delete -> TSV on stdout: groups \t tabs \t keys
// update -> sets title and color of existing groups from a TSV file of
//           guid \t color \t title lines; prints the number of groups changed
// Exit: 0 ok · 1 error (message on stderr)

import { readFileSync } from 'node:fs'
import { ClassicLevel } from 'classic-level'

const PREFIX = 'saved_tab_group-'
const DT = PREFIX + 'dt-'
const MD = PREFIX + 'md-'

// Field numbers verified by walking the real store; see the plan/README.
// Wrapper: 2 = specifics. Specifics: 1 guid, 4 group, 5 tab.
// Group: 2 title, 3 color. Tab: 1 parent group guid, 3 url, 4 title.
const F_SPECIFICS = 2
const F_GUID = 1
const F_GROUP = 4
const F_TAB = 5
const F_GROUP_TITLE = 2
const F_GROUP_COLOR = 3
const F_TAB_PARENT = 1

// Cosmetic only — mirrors the order of Chrome's SavedTabGroupColor enum.
const COLORS = ['unspecified', 'grey', 'blue', 'red', 'yellow', 'green',
  'pink', 'purple', 'cyan', 'orange']

function die (msg) {
  process.stderr.write(`tabgroups: ${msg}\n`)
  process.exit(1)
}

// --- minimal protobuf wire-format reader -----------------------------------
// Only enough to pull known scalar/submessage fields out of records Chrome
// wrote. Unknown fields are skipped, so newer Chrome versions adding fields
// stay readable.

function varint (buf, i) {
  let result = 0
  let shift = 0
  while (i < buf.length) {
    const byte = buf[i++]
    result += (byte & 0x7f) * Math.pow(2, shift)
    if (!(byte & 0x80)) break
    shift += 7
  }
  return [result, i]
}

// --- minimal protobuf writer -------------------------------------------------
// update has to edit a record Chrome wrote without losing the fields this file
// does not know about, so it works on raw entries rather than decoded values.

function encVarint (n) {
  const bytes = []
  while (n > 127) { bytes.push((n & 0x7f) | 0x80); n = Math.floor(n / 128) }
  bytes.push(n)
  return Buffer.from(bytes)
}

const lenField = (field, body) =>
  Buffer.concat([encVarint((field << 3) | 2), encVarint(body.length), body])
const intField = (field, n) => Buffer.concat([encVarint(field << 3), encVarint(n)])

// Split a message into its raw entries, order preserved.
function entries (buf) {
  const out = []
  let i = 0
  while (i < buf.length) {
    const start = i
    let tag
    ;[tag, i] = varint(buf, i)
    const type = tag & 7
    let body = null
    if (type === 0) {
      ;[, i] = varint(buf, i)
    } else if (type === 2) {
      let len
      ;[len, i] = varint(buf, i)
      body = buf.subarray(i, i + len)
      i += len
    } else if (type === 5) {
      i += 4
    } else if (type === 1) {
      i += 8
    } else {
      throw new Error(`unknown wire type ${type}`)
    }
    out.push({ field: tag >>> 3, raw: buf.subarray(start, i), body })
  }
  return out
}

// Rebuild buf with the length-delimited `field` run through fn(body).
function editField (buf, field, fn) {
  let hit = false
  const out = entries(buf).map(e => {
    if (e.field !== field || !e.body || hit) return e.raw
    hit = true
    return lenField(field, fn(e.body))
  })
  if (!hit) throw new Error(`no field ${field}`)
  return Buffer.concat(out)
}

function walk (buf) {
  const fields = {}
  let i = 0
  while (i < buf.length) {
    let tag
    ;[tag, i] = varint(buf, i)
    const field = tag >>> 3
    const type = tag & 7
    let value
    if (type === 0) {
      ;[value, i] = varint(buf, i)
    } else if (type === 2) {
      let len
      ;[len, i] = varint(buf, i)
      value = buf.subarray(i, i + len)
      i += len
    } else if (type === 5) {
      value = buf.readUInt32LE(i); i += 4
    } else if (type === 1) {
      value = buf.readBigUInt64LE(i); i += 8
    } else {
      break // unknown wire type: the rest can't be trusted
    }
    if (fields[field] === undefined) fields[field] = value
  }
  return fields
}

const str = v => (Buffer.isBuffer(v) ? v.toString('utf8') : '')
const sub = v => (Buffer.isBuffer(v) ? walk(v) : null)

// --- store access ----------------------------------------------------------

// Read every saved_tab_group record, split into groups and their tabs.
// A record is a group if it carries the group submessage, a tab if it carries
// the tab submessage — no guessing from the payload text.
async function read (db) {
  const groups = []
  const tabs = []
  for await (const [key, value] of db.iterator({ valueEncoding: 'buffer' })) {
    if (!key.startsWith(DT)) continue
    const specifics = sub(walk(Buffer.from(value))[F_SPECIFICS])
    if (!specifics) continue
    const guid = str(specifics[F_GUID]) || key.slice(DT.length)
    const group = sub(specifics[F_GROUP])
    const tab = sub(specifics[F_TAB])
    if (group) {
      groups.push({
        guid,
        title: str(group[F_GROUP_TITLE]),
        color: COLORS[group[F_GROUP_COLOR] ?? 0] ?? 'unknown'
      })
    } else if (tab) {
      tabs.push({ guid, parent: str(tab[F_TAB_PARENT]) })
    }
  }
  return { groups, tabs }
}

function matcher (filter, regex, all) {
  if (all) return () => true
  if (regex) {
    let re
    try {
      re = new RegExp(filter, 'i')
    } catch (err) {
      die(`invalid regex: ${err.message}`)
    }
    return title => re.test(title)
  }
  const needle = filter.toLowerCase()
  return title => title.toLowerCase().includes(needle)
}

// --- commands --------------------------------------------------------------

async function list (db, { filter, regex, all }) {
  const { groups, tabs } = await read(db)
  const matches = matcher(filter, regex, all)
  const counts = new Map()
  for (const tab of tabs) counts.set(tab.parent, (counts.get(tab.parent) ?? 0) + 1)

  const out = []
  for (const group of groups) {
    if (!matches(group.title)) continue
    // Tabs and newlines would corrupt the TSV the caller parses.
    const title = group.title.replace(/[\t\r\n]+/g, ' ')
    out.push(`${group.guid}\t${counts.get(group.guid) ?? 0}\t${group.color}\t${title}`)
  }
  if (out.length) process.stdout.write(out.join('\n') + '\n')
}

async function remove (db, guids) {
  const wanted = new Set(guids)
  const { groups, tabs } = await read(db)
  const known = new Set(groups.map(g => g.guid))
  for (const guid of wanted) {
    if (!known.has(guid)) die(`no such group: ${guid}`)
  }

  // Both key flavours for the group and for every tab that belongs to it.
  // Deleting an absent -md- key is a no-op, so records that never synced
  // need no special handling.
  const ops = []
  const kill = guid => ops.push({ type: 'del', key: DT + guid }, { type: 'del', key: MD + guid })
  for (const guid of wanted) kill(guid)
  let tabCount = 0
  for (const tab of tabs) {
    if (!wanted.has(tab.parent)) continue
    kill(tab.guid)
    tabCount++
  }

  // Belt and braces: nothing outside saved_tab_group- may ever be deleted.
  for (const op of ops) {
    if (!op.key.startsWith(PREFIX)) die(`refusing to delete foreign key: ${op.key}`)
  }

  await db.batch(ops)
  process.stdout.write(`${wanted.size}\t${tabCount}\t${ops.length}\n`)
}

async function update (db, file) {
  const wanted = new Map()
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    if (!line) continue
    const [guid, color, ...title] = line.split('\t')
    const index = COLORS.indexOf(color)
    if (!guid || index < 1) die(`bad line (guid, color, title expected): ${line}`)
    wanted.set(guid, { index, title: title.join(' ') })
  }

  const ops = []
  for (const guid of wanted.keys()) {
    const value = await db.get(DT + guid, { valueEncoding: 'buffer' }).catch(() => null)
    if (!value) die(`no such group: ${guid}`)
    const { index, title } = wanted.get(guid)
    const edited = editField(Buffer.from(value), F_SPECIFICS, specifics =>
      editField(specifics, F_GROUP, group => Buffer.concat([
        ...entries(group).filter(e => e.field !== F_GROUP_TITLE && e.field !== F_GROUP_COLOR).map(e => e.raw),
        lenField(F_GROUP_TITLE, Buffer.from(title, 'utf8')),
        intField(F_GROUP_COLOR, index)
      ])))
    ops.push({ type: 'put', key: DT + guid, value: edited })
  }

  // Only group records are rewritten, and only by their own -dt- key.
  for (const op of ops) {
    if (!op.key.startsWith(DT)) die(`refusing to write foreign key: ${op.key}`)
  }

  await db.batch(ops, { valueEncoding: 'buffer' })
  process.stdout.write(`${ops.length}\n`)
}

// --- entry point -----------------------------------------------------------

const argv = process.argv.slice(2)
const command = argv.shift()
const opts = { db: '', filter: '', regex: false, all: false, file: '' }
const guids = []

while (argv.length) {
  const arg = argv.shift()
  switch (arg) {
    case '--db': opts.db = argv.shift() ?? die('--db expects a path'); break
    case '--filter': opts.filter = argv.shift() ?? die('--filter expects a value'); break
    case '--guid': guids.push(argv.shift() ?? die('--guid expects a value')); break
    case '--file': opts.file = argv.shift() ?? die('--file expects a path'); break
    case '--regex': opts.regex = true; break
    case '--all': opts.all = true; break
    default: die(`unknown argument: ${arg}`)
  }
}

if (!opts.db) die('--db is required')

// createIfMissing:false matters — a typo'd path would otherwise silently
// create an empty store and report "no groups" instead of failing.
const db = new ClassicLevel(opts.db, { createIfMissing: false })
try {
  await db.open()
} catch (err) {
  // The usual cause is Chrome still holding the lock; the caller gates on
  // that already, so anything reaching here is worth reporting verbatim.
  die(`cannot open ${opts.db}: ${err.message}`)
}

try {
  if (command === 'list') {
    await list(db, opts)
  } else if (command === 'delete') {
    if (!guids.length) die('delete needs at least one --guid')
    await remove(db, guids)
  } else if (command === 'update') {
    if (!opts.file) die('update needs --file')
    await update(db, opts.file)
  } else {
    die(`unknown command: ${command ?? '(none)'}`)
  }
} finally {
  await db.close()
}
