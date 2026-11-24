// Design-consistency lint for the .dc.html mockups (static markup only). Rules live in /DESIGN.md.
//   node lint.cjs [dir-with-.dc.html-files]      (exit code 1 when anything is flagged)
// Measures every control, badge and avatar and flags anything that breaks DESIGN.md:
//   1. a control height that is not on the ruler (36 / 44 / 56 / 64 / 80)
//   2. controls in one row that do not share a height
//   3. a control radius other than 10 (a container around a control = inner radius + its inset; the
//      segmented control's inner buttons = 10 - inset; 64px+ transport / play controls are circles)
//   4. a 28px badge whose radius is not 10
//   5. an [data-avatar] that is not concentric with its parent (radius = parent radius - inset), or a
//      96px+ tile that is not a 28% squircle or is nested in a rounded parent
// Not measured as controls: profile tiles (buttons taller than 100px), underline tabs (radius 0).
const fs = require('fs')
const path = require('path')
const { chromium } = require('playwright')

const DIR = process.argv[2] || path.join(__dirname, 'project')
const RULER = [36, 44, 56, 64, 80]
const CTL_RADIUS = 10
const TRANSPORT = [64, 80]
const BOARDS = fs.readdirSync(DIR).filter((f) => f.endsWith('.dc.html')).sort()

;(async () => {
  const browser = await chromium.launch()
  const page = await browser.newPage({ viewport: { width: 1200, height: 675 } })
  let problems = 0
  for (const f of BOARDS) {
    const src = fs.readFileSync(path.join(DIR, f), 'utf8')
    const inner = (src.match(/<x-dc>([\s\S]*?)<\/x-dc>/) || [, ''])[1].replace(/<helmet>[\s\S]*?<\/helmet>/, '')
    await page.setContent(`<!doctype html><meta charset="utf-8"><style>body{margin:0}button{font-family:inherit}input::placeholder{color:#9A9085;opacity:1}</style>${inner}`)
    const rows = await page.evaluate(() => {
      const out = []
      const vis = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0 }
      const px = (v, r) => (/%$/.test(v) ? (parseFloat(v) / 100) * Math.min(r.width, r.height) : parseFloat(v) || 0)
      const label = (el) => (el.getAttribute('aria-label') || el.value || el.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 24)
      const rec = (el, extra) => { const r = el.getBoundingClientRect(), cs = getComputedStyle(el)
        return Object.assign({ tag: el.tagName.toLowerCase(), label: label(el), x: r.x, y: r.y, w: r.width, h: r.height, right: r.right, bottom: r.bottom, radius: px(cs.borderTopLeftRadius, r) }, extra) }
      document.querySelectorAll('button, input[type=text], [role=status], [role=group]').forEach((el) => {
        if (!vis(el)) return
        const r = el.getBoundingClientRect(), cs = getComputedStyle(el)
        if (el.tagName === 'BUTTON') {
          if (r.height > 100) return                                           // profile tile
          if (parseFloat(cs.borderTopLeftRadius) === 0) return                 // underline tab
          if (el.parentElement.getAttribute('role') === 'group') {             // segmented inner button
            const p = el.parentElement.getBoundingClientRect()
            out.push(rec(el, { kind: 'segInner', off: Math.min(r.x - p.x, r.y - p.y), parentRadius: px(getComputedStyle(el.parentElement).borderTopLeftRadius, p) }))
            return
          }
        }
        out.push(rec(el, { kind: 'control' }))
      })
      document.querySelectorAll('a[href]').forEach((el) => { if (vis(el) && el.getBoundingClientRect().height <= 80) out.push(rec(el, { kind: 'control' })) })
      // badges: use layout height (offsetHeight) so a scaled, focused card still counts
      document.querySelectorAll('[style*="height:28px"], [style*="height: 28px"]').forEach((el) => { if (vis(el) && el.offsetHeight === 28) out.push(rec(el, { kind: 'badge' })) })
      document.querySelectorAll('[data-avatar]').forEach((el) => {
        if (!vis(el)) return
        const r = el.getBoundingClientRect(), p = el.parentElement.getBoundingClientRect()
        out.push({ kind: 'avatar', size: Math.round(r.width), radius: px(getComputedStyle(el).borderTopLeftRadius, r), pct: /%/.test(getComputedStyle(el).borderTopLeftRadius),
          parentRadius: px(getComputedStyle(el.parentElement).borderTopLeftRadius, p), off: Math.min(r.x - p.x, r.y - p.y, p.right - r.right, p.bottom - r.bottom) })
      })
      return out
    })
    const controls = rows.filter((r) => r.kind === 'control')
    const bad = []
    controls.forEach((c) => { if (!RULER.includes(Math.round(c.h))) bad.push(`height ${Math.round(c.h * 10) / 10} is off the ruler: ${c.tag} "${c.label}"`) })
    const byRow = {}
    controls.forEach((c) => { const k = Math.round((c.y + c.h / 2) / 6); (byRow[k] = byRow[k] || []).push(c) })
    const contains = (a, b) => a !== b && b.x >= a.x - 0.5 && b.y >= a.y - 0.5 && b.right <= a.right + 0.5 && b.bottom <= a.bottom + 0.5
    Object.values(byRow).forEach((row) => {
      const g = row.filter((c) => !row.some((o) => contains(c, o)))
      const hs = [...new Set(g.map((c) => Math.round(c.h)))]
      if (g.length > 1 && hs.length > 1 && !hs.every((h) => TRANSPORT.includes(h)))
        bad.push(`row mixes heights ${hs.join('/')}: ${g.map((c) => `"${c.label}"(${Math.round(c.h)})`).join(', ')}`)
    })
    controls.forEach((c) => {
      const circle = Math.abs(c.w - c.h) < 1 && c.h >= 64 && Math.abs(c.radius - c.h / 2) < 1      // transport / play: allowed circles
      if (circle) return
      let want = CTL_RADIUS, why = `${CTL_RADIUS}px control radius`
      const kids = controls.filter((o) => contains(c, o))                                           // a container around a control (toast): inner radius + inset
      if (kids.length) { const k = kids[0]; const off = Math.min(k.x - c.x, k.y - c.y); want = k.radius + off; why = `inner radius ${k.radius} + inset ${Math.round(off)}` }
      if (Math.abs(c.radius - want) > 1.5) bad.push(`radius ${Math.round(c.radius * 10) / 10} should be ${want} (${why}): ${c.tag} "${c.label}"`)
    })
    rows.filter((r) => r.kind === 'segInner').forEach((s) => { const want = s.parentRadius - s.off
      if (Math.abs(s.radius - want) > 1.5) bad.push(`segmented inner button radius ${s.radius} should be ${want} (outer ${s.parentRadius} - inset ${Math.round(s.off)}): "${s.label}"`) })
    rows.filter((r) => r.kind === 'badge').forEach((b) => { if (Math.abs(b.radius - CTL_RADIUS) > 1) bad.push(`28px badge radius ${b.radius} should be ${CTL_RADIUS}: ${b.tag} "${b.label}"`) })
    rows.filter((r) => r.kind === 'avatar').forEach((a) => {
      if (a.size >= 96) {
        if (!a.pct || Math.abs(a.radius - a.size * 0.28) > 1.5) bad.push(`avatar tile ${a.size}px should be a 28% squircle (radius ${a.radius})`)
        if (a.parentRadius > 0) bad.push(`avatar tile ${a.size}px is nested in a rounded parent (radius ${a.parentRadius})`)
      } else {
        const want = a.parentRadius - a.off
        if (Math.abs(a.radius - want) > 1.5) bad.push(`avatar ${a.size}px radius ${a.radius} is not concentric: parent radius ${a.parentRadius} - inset ${Math.round(a.off)} = ${want}`)
      }
    })
    const n = (k) => rows.filter((r) => r.kind === k).length
    console.log(`\n== ${f}  (${controls.length} controls, ${n('badge')} badges, ${n('avatar')} avatars)`)
    console.log(bad.length ? bad.map((b) => '   x ' + b).join('\n') : '   ok')
    problems += bad.length
  }
  console.log(`\nTOTAL PROBLEMS: ${problems}`)
  await browser.close()
  process.exit(problems ? 1 : 0)
})()
