// Design-consistency lint for the .dc.html mockups (static markup only). Rules live in /DESIGN.md.
//   node lint.cjs [dir-with-.dc.html-files]      (exit code 1 when anything is flagged)
// Measures every control and avatar and flags anything that breaks DESIGN.md:
//   1. a control height that is not on the ruler (36 / 44 / 56 / 64 / 80)
//   2. controls in one row that do not share a height
//   3. a single-line control that is not a pill (radius = height / 2)
//   4. an avatar below 96 px that is not a circle, or a 96 px+ tile nested in a rounded parent
// Not measured as controls: profile tiles (buttons taller than 100 px), underline tabs (radius 0),
// the inner buttons of a segmented control (the [role=group] wrapper is measured instead), the scrub track.
const fs = require('fs')
const path = require('path')
const { chromium } = require('playwright')

const DIR = process.argv[2] || path.join(__dirname, 'project')
const RULER = [36, 44, 56, 64, 80]
const TRANSPORT = [64, 80]                          // the player's skip / play discs may share a row at different sizes
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
      const label = (el) => (el.getAttribute('aria-label') || el.value || el.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 24)
      // a "50%" radius is half the shorter side in px; computed style keeps the % sign
      const px = (v, r) => (/%$/.test(v) ? (parseFloat(v) / 100) * Math.min(r.width, r.height) : parseFloat(v) || 0)
      const push = (el, tag) => { const r = el.getBoundingClientRect(), cs = getComputedStyle(el)
        out.push({ kind: 'control', tag, label: label(el), x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10, right: r.right, bottom: r.bottom, radius: px(cs.borderTopLeftRadius, r) }) }
      document.querySelectorAll('button, input[type=text], [role=status], [role=group]').forEach((el) => {
        if (!vis(el)) return
        const r = el.getBoundingClientRect(), cs = getComputedStyle(el)
        if (el.tagName === 'BUTTON') {
          if (el.parentElement.getAttribute('role') === 'group') return        // segmented inner button
          if (r.height > 100) return                                           // profile tile
          if (parseFloat(cs.borderTopLeftRadius) === 0) return                 // underline tab
        }
        push(el, el.tagName.toLowerCase())
      })
      document.querySelectorAll('a[href]').forEach((el) => { if (vis(el) && el.getBoundingClientRect().height <= 80) push(el, 'a') })
      document.querySelectorAll('span, div').forEach((el) => {
        const st = el.getAttribute('style') || ''
        if (!/border-radius:\s*(28%|50%)/.test(st)) return
        const r = el.getBoundingClientRect()
        if (!vis(el) || Math.abs(r.width - r.height) > 1 || r.width < 24 || r.width > 160) return
        const p = el.parentElement, pcs = getComputedStyle(p)
        out.push({ kind: 'avatar', shape: /28%/.test(st) ? 'squircle' : 'circle', size: Math.round(r.width), parentRadius: parseFloat(pcs.borderTopLeftRadius) || 0 })
      })
      return out
    })
    const controls = rows.filter((r) => r.kind === 'control')
    const bad = []
    controls.forEach((c) => { if (!RULER.includes(Math.round(c.h))) bad.push(`height ${c.h} is off the ruler: ${c.tag} "${c.label}"`) })
    const byRow = {}
    controls.forEach((c) => { const k = Math.round((c.y + c.h / 2) / 6); (byRow[k] = byRow[k] || []).push(c) })
    const contains = (a, b) => a !== b && b.x >= a.x - 0.5 && b.y >= a.y - 0.5 && b.right <= a.right + 0.5 && b.bottom <= a.bottom + 0.5
    Object.values(byRow).forEach((row) => {
      const g = row.filter((c) => !row.some((o) => contains(c, o)))     // a container (toast, segmented group) is not compared with its own children
      const hs = [...new Set(g.map((c) => Math.round(c.h)))]
      if (g.length > 1 && hs.length > 1 && !hs.every((h) => TRANSPORT.includes(h)))
        bad.push(`row mixes heights ${hs.join('/')}: ${g.map((c) => `"${c.label}"(${Math.round(c.h)})`).join(', ')}`)
    })
    controls.forEach((c) => { if (c.radius < 900 && Math.abs(c.radius - c.h / 2) > 1) bad.push(`not a pill (radius ${c.radius}, height ${c.h}): ${c.tag} "${c.label}"`) })
    rows.filter((r) => r.kind === 'avatar').forEach((a) => {
      if (a.size < 96 && a.shape !== 'circle') bad.push(`avatar ${a.size}px is a squircle; below 96px it must be a circle`)
      if (a.size >= 96 && a.parentRadius > 0) bad.push(`avatar tile ${a.size}px is nested in a rounded parent (radius ${a.parentRadius})`)
    })
    console.log(`\n== ${f}  (${controls.length} controls, ${rows.length - controls.length} avatars)`)
    console.log(bad.length ? bad.map((b) => '   x ' + b).join('\n') : '   ok')
    problems += bad.length
  }
  console.log(`\nTOTAL PROBLEMS: ${problems}`)
  await browser.close()
  process.exit(problems ? 1 : 0)
})()
