import { createClient } from 'npm:@supabase/supabase-js@2'
import postgres from 'npm:postgres@3'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const db = postgres(Deno.env.get('SUPABASE_DB_URL')!, { prepare: false, max: 2 })
const service = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })

const BUSY = 'Finn is in heavy traffic right now. Try again later.'

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

const PERSONA = `You are Finn, a small friendly fish who lives inside Fishi, a messaging app.
Reply like a friend texting: short, warm, clear. Plain text only, no markdown.
You can see photos and videos, and hear voice messages, that people send or reply to.
If you are unsure, say so. Never claim you did something unless a tool confirmed it.`

const HELPER = `This is the user's own chat with you. You can also help them message people:
call list_contacts to find who they mean, then send_message with the exact text they asked for.
If more than one contact could match, ask which one before sending. Confirm briefly after sending.`

type Row = Record<string, any>

async function signed(path: string) {
  const { data } = await service.storage.from('media').createSignedUrl(path, 900)
  return data?.signedUrl
}

async function mediaPart(m: Row) {
  if (!m?.media_path) return null
  if (m.kind === 'image') {
    const url = await signed(m.media_path)
    return url ? { type: 'image_url', image_url: { url } } : null
  }
  if (m.kind === 'video') {
    const url = await signed(m.media_path)
    return url ? { type: 'video_url', video_url: { url } } : null
  }
  if (m.kind === 'audio') {
    const { data } = await service.storage.from('media').download(m.media_path)
    if (!data) return null
    const bytes = new Uint8Array(await data.arrayBuffer())
    let bin = ''
    for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
    const format = (m.media_path.split('.').pop() ?? 'm4a').toLowerCase()
    return { type: 'input_audio', input_audio: { data: btoa(bin), format } }
  }
  return null
}

type Key = { id: string; label: string; endpoint: string; key: string }

function keysOf(cfg: Row): Key[] {
  const list: Key[] = (Array.isArray(cfg.api_keys) ? cfg.api_keys : []).filter((k: Row) => k?.key && k?.endpoint)
  if (!list.length && cfg.api_key) list.push({ id: 'legacy', label: 'Key', endpoint: cfg.endpoint, key: cfg.api_key })
  return list
}

function modelsOf(cfg: Row): string[] {
  const list = Array.isArray(cfg.models) && cfg.models.length ? cfg.models : [cfg.model]
  return list.filter(Boolean)
}

function modelFor(endpoint: string, model: string) {
  if (/openrouter/i.test(endpoint) && !model.includes('/')) return `google/${model}`
  if (/googleapis/i.test(endpoint) && model.startsWith('google/')) return model.slice('google/'.length)
  return model
}

async function complete(cfg: Row, messages: unknown[], tools: unknown[]) {
  const keys = keysOf(cfg)
  const models = modelsOf(cfg)
  for (let round = 0; round < 5; round++) {
    let limited = false
    for (const k of keys) {
      for (const m of models) {
        const model = modelFor(k.endpoint, m)
        try {
          const res = await fetch(`${k.endpoint.replace(/\/$/, '')}/chat/completions`, {
            method: 'POST',
            headers: { Authorization: `Bearer ${k.key}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model, messages, ...(tools.length ? { tools } : {}) }),
          })
          if (res.ok) {
            const data = await res.json()
            const choice = data.choices?.[0]?.message
            if (choice) return choice
            continue
          }
          console.error('finn upstream', k.label, model, res.status, (await res.text()).slice(0, 300))
          if (res.status === 401 || res.status === 403) break
          if (res.status === 429) limited = true
        } catch (e) {
          console.error('finn fetch', k.label, model, e)
          limited = true
        }
      }
    }
    if (!limited) break
    await sleep(2000)
  }
  return null
}

Deno.serve(async (req) => {
  const auth = req.headers.get('Authorization') ?? ''
  const asUser = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: auth } } })
  const { data: { user } } = await asUser.auth.getUser(auth.replace('Bearer ', ''))
  if (!user) return json({ error: 'unauthorized' }, 401)

  const { message_id } = await req.json()
  const { data: msg } = await service.from('messages').select('*').eq('id', message_id).single()
  if (!msg || msg.sender_id !== user.id) return json({ error: 'not_found' }, 404)

  const { data: chat } = await service.from('chats').select('*').eq('id', msg.chat_id).single()
  const { data: finn } = await service.from('profiles').select('id').eq('username', 'finn').single()
  const inOwnChat = chat.kind === 'finn'
  const called = inOwnChat || (msg.mentions ?? []).includes(finn.id) || /(^|\W)@finn\b/i.test(msg.body)
  if (!called) return json({ skipped: true })

  const broadcast = () =>
    fetch(`${SUPABASE_URL}/realtime/v1/api/broadcast`, {
      method: 'POST',
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ messages: [{ topic: `room:${chat.id}`, event: 'typing', payload: { id: finn.id, name: 'Finn' } }] }),
    }).catch(() => {})
  broadcast()
  const typing = setInterval(broadcast, 2000)

  const reply = async (body: string) => {
    await service.from('messages').insert({
      chat_id: chat.id,
      sender_id: finn.id,
      body: body.slice(0, 8000),
      reply_to: inOwnChat ? null : msg.id,
    })
  }

  try {
    const [cfg] = await db`select * from private.finn_config where id = 1`
    if (!cfg || !keysOf(cfg).length) {
      await reply(BUSY)
      return json({ ok: false })
    }

    const memory = await db`select id, fact from private.finn_memory where user_id = ${user.id} order by id desc limit 40`
    const { data: history } = await service
      .from('messages')
      .select('id, sender_id, kind, body, created_at, profiles:sender_id(display_name, username)')
      .eq('chat_id', chat.id)
      .is('deleted_at', null)
      .order('created_at', { ascending: false })
      .limit(30)

    const convo: Row[] = []
    for (const h of (history ?? []).reverse()) {
      if (h.id === msg.id || h.kind === 'system') continue
      if (h.sender_id === finn.id) {
        convo.push({ role: 'assistant', content: h.body })
      } else {
        const who = inOwnChat ? '' : `${h.profiles?.display_name} (@${h.profiles?.username}): `
        const text = h.body || `[sent a ${h.kind}]`
        convo.push({ role: 'user', content: who + text })
      }
    }

    const parts: Row[] = []
    const { data: me } = await service.from('profiles').select('display_name, username').eq('id', user.id).single()
    let target = msg
    if (msg.reply_to) {
      const { data: replied } = await service.from('messages').select('*').eq('id', msg.reply_to).single()
      if (replied) {
        parts.push({ type: 'text', text: `[replying to a ${replied.kind}${replied.body ? `: "${replied.body}"` : ''}]` })
        if (replied.media_path) target = replied
      }
    }
    const media = await mediaPart(target)
    if (msg.media_path && target !== msg) {
      const own = await mediaPart(msg)
      if (own) parts.push(own)
    }
    if (media) parts.push(media)
    const prefix = inOwnChat ? '' : `${me?.display_name} (@${me?.username}): `
    parts.push({ type: 'text', text: prefix + (msg.body || '[no text]') })
    convo.push({ role: 'user', content: parts })

    const facts = memory.map((m: Row) => `#${m.id}: ${m.fact}`).join('\n')
    const system = [
      PERSONA,
      cfg.system_prompt ?? '',
      `You are talking with ${me?.display_name} (@${me?.username}).`,
      inOwnChat ? HELPER : 'You were mentioned in a chat. Answer the person who called you.',
      facts ? `Things you remember about this user:\n${facts}` : 'You do not remember anything about this user yet.',
      'Use remember when the user shares a lasting preference or fact about themselves, and forget when asked.',
    ].filter(Boolean).join('\n\n')

    const tools: Row[] = [
      { type: 'function', function: { name: 'remember', description: 'Save a short lasting fact about the user.', parameters: { type: 'object', properties: { fact: { type: 'string' } }, required: ['fact'] } } },
      { type: 'function', function: { name: 'forget', description: 'Delete a remembered fact by its number.', parameters: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] } } },
    ]
    if (inOwnChat) {
      tools.push(
        { type: 'function', function: { name: 'list_contacts', description: 'List the people and groups this user chats with.', parameters: { type: 'object', properties: {} } } },
        { type: 'function', function: { name: 'send_message', description: 'Send a text message from the user to a contact (by username) or a group (by group_id).', parameters: { type: 'object', properties: { username: { type: 'string' }, group_id: { type: 'string' }, text: { type: 'string' } }, required: ['text'] } } },
      )
    }

    const messages: Row[] = [{ role: 'system', content: system }, ...convo]

    for (let round = 0; round < 5; round++) {
      const out = await complete(cfg, messages, tools)
      if (!out) {
        await reply(BUSY)
        return json({ ok: false })
      }
      const calls = out.tool_calls ?? []
      if (!calls.length) {
        await reply((out.content ?? '').trim() || '...')
        return json({ ok: true })
      }
      messages.push(out)
      for (const call of calls) {
        let args: Row = {}
        try { args = JSON.parse(call.function.arguments || '{}') } catch { /* empty */ }
        let result: unknown = 'ok'
        const name = call.function.name
        if (name === 'remember' && args.fact) {
          await db`insert into private.finn_memory (user_id, fact) values (${user.id}, ${String(args.fact).slice(0, 500)})`
        } else if (name === 'forget') {
          await db`delete from private.finn_memory where id = ${Number(args.id)} and user_id = ${user.id}`
        } else if (name === 'list_contacts' && inOwnChat) {
          const { data: rows } = await asUser
            .from('chat_members')
            .select('chat_id, chats(kind, name), profiles(username, display_name, is_bot)')
            .neq('user_id', user.id)
          const people = new Map<string, string>()
          const groups = new Map<string, string>()
          for (const r of rows ?? []) {
            if (r.chats?.kind === 'group') groups.set(r.chat_id, r.chats.name)
            else if (r.chats?.kind === 'direct' && !r.profiles?.is_bot) people.set(r.profiles.username, r.profiles.display_name)
          }
          result = {
            people: [...people].map(([username, name]) => ({ username, name })),
            groups: [...groups].map(([group_id, name]) => ({ group_id, name })),
          }
        } else if (name === 'send_message' && inOwnChat) {
          let target: string | null = null
          if (args.group_id) {
            const { data: ok } = await asUser.rpc('is_member', { chat: args.group_id })
            target = ok ? args.group_id : null
          } else if (args.username) {
            const { data: p } = await service.from('profiles').select('id').eq('username', String(args.username).toLowerCase().replace(/^@/, '')).maybeSingle()
            if (p) {
              const { data: cid } = await asUser.rpc('open_direct', { other: p.id })
              target = cid
            }
          }
          if (!target) {
            result = { error: 'Could not find that contact or group.' }
          } else {
            const { error } = await asUser.from('messages').insert({
              chat_id: target,
              sender_id: user.id,
              body: String(args.text).slice(0, 8000),
              media_meta: { via: 'finn' },
            })
            result = error ? { error: error.message } : { sent: true }
          }
        } else {
          result = { error: 'unknown tool' }
        }
        messages.push({ role: 'tool', tool_call_id: call.id, content: JSON.stringify(result) })
      }
    }
    await reply(BUSY)
    return json({ ok: false })
  } finally {
    clearInterval(typing)
  }
})
