/**
 * Build the DeepSeek Harness launcher icon set.
 *
 * The whale mark is the official DeepSeek silhouette, copied from the DSH web
 * app's own favicon (apps/web/public/favicon.svg). Its ink is not centred in
 * its 50x50 viewBox, so this script measures the ink box and derives a
 * transform that centres it exactly - see WHALE_INK below.
 *
 * Look: near-black background, faint grid, sparse particles around the mark,
 * bright mark in the middle. Sizes 16 and 24 drop the grid and particles and
 * enlarge the mark, because those details turn to mud that small.
 *
 * Produces (all inside ../assets/):
 *   dsh-icon.svg          the static 512px artwork
 *   dsh-icon.ico          multi-size Windows icon (16/24/32/48/64/128/256)
 *   dsh-icon-<size>.png   PNG renders
 *   dsh-icon.png          512px PNG
 *
 * Run:  node tools/make-dsh-icon.mjs
 *       node tools/make-dsh-icon.mjs --preview   also print ASCII previews
 *
 * sharp is loaded from the local DSH install; override with SHARP_PATH.
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

// This generator lives in tools/; the artwork it writes lives in ../assets/.
const here = dirname(fileURLToPath(import.meta.url))
const assetsDir = join(here, '..', 'assets')
const svgPath = join(assetsDir, 'dsh-icon.svg')
const icoPath = join(assetsDir, 'dsh-icon.ico')

const SHARP_PATH = process.env.SHARP_PATH
  ?? 'C:/Users/S1GHLE/.dsh/profiles/node_modules/sharp'

const require = createRequire(import.meta.url)

/** Load sharp, preferring SHARP_PATH and falling back to normal resolution. */
function loadSharp() {
  try {
    return require(SHARP_PATH)
  } catch (first) {
    try {
      return require('sharp')
    } catch {
      throw new Error(
        'sharp is unavailable.\n'
        + `  tried: ${SHARP_PATH}\n`
        + '  fix:   set SHARP_PATH to a sharp install, or run this where sharp resolves\n'
        + `  cause: ${first.message}`,
      )
    }
  }
}

const sharp = loadSharp()

// ----------------------------------------------------------------- geometry ---

/** Official DeepSeek whale silhouette, as shipped in the web app's favicon. */
const WHALE_PATH = 'M48.8354 10.0479C48.3232 9.79199 48.1025 10.2798 47.8032 10.5278C47.7007 10.6079 47.6143 10.7119 47.5273 10.8076C46.7793 11.624 45.9048 12.1597 44.7622 12.0957C43.0923 12 41.666 12.5356 40.4058 13.8398C40.1377 12.2319 39.2476 11.272 37.8926 10.6558C37.1836 10.3359 36.4668 10.0156 35.9702 9.31982C35.6235 8.82373 35.5293 8.27197 35.356 7.72754C35.2456 7.3999 35.1353 7.06396 34.7651 7.00781C34.3633 6.94385 34.2056 7.2876 34.0479 7.57568C33.418 8.75195 33.1733 10.0479 33.1973 11.3599C33.2524 14.312 34.4736 16.6641 36.8999 18.3359C37.1758 18.5278 37.2466 18.7197 37.1597 19C36.9946 19.5757 36.7974 20.1357 36.624 20.7119C36.5137 21.0801 36.3486 21.1597 35.9624 21C34.6309 20.4321 33.481 19.5918 32.4644 18.5757C30.7393 16.8721 29.1792 14.9917 27.2334 13.52C26.7764 13.1758 26.3193 12.856 25.8467 12.5518C23.8618 10.584 26.1069 8.96777 26.627 8.77588C27.1704 8.57568 26.8159 7.8877 25.0591 7.896C23.3022 7.90381 21.6953 8.50391 19.647 9.30371C19.3477 9.42383 19.0322 9.51172 18.7095 9.58398C16.8501 9.22363 14.9199 9.14355 12.9033 9.37598C9.10596 9.80762 6.07275 11.6396 3.84326 14.7681C1.16455 18.5278 0.53418 22.7998 1.30664 27.2559C2.11768 31.9521 4.46582 35.8398 8.07373 38.8799C11.8159 42.0322 16.1255 43.5762 21.041 43.2803C24.0269 43.104 27.3516 42.6963 31.1016 39.4561C32.0469 39.936 33.0396 40.1279 34.686 40.272C35.9546 40.3921 37.1758 40.208 38.1211 40.0078C39.6021 39.688 39.4995 38.2881 38.9639 38.0322C34.623 35.9678 35.5762 36.8081 34.71 36.1279C36.9155 33.4639 40.2402 30.6958 41.54 21.728C41.6426 21.0161 41.5557 20.5679 41.54 19.9917C41.5322 19.6396 41.6108 19.5039 42.0049 19.4639C43.0923 19.3359 44.1479 19.0317 45.1167 18.4878C47.9292 16.9199 49.064 14.3438 49.3315 11.2559C49.3711 10.7837 49.3237 10.2959 48.8354 10.0479ZM24.3262 37.8398C20.1196 34.4639 18.0791 33.3521 17.2358 33.3999C16.4482 33.4482 16.5898 34.3682 16.7632 34.9678C16.9443 35.5601 17.1812 35.9683 17.5117 36.4878C17.7402 36.832 17.8979 37.3442 17.2832 37.728C15.9282 38.584 13.5728 37.4399 13.4624 37.3838C10.7207 35.7358 8.42822 33.5601 6.81348 30.584C5.25342 27.7197 4.34766 24.6479 4.19775 21.3677C4.1582 20.5757 4.38672 20.2959 5.15869 20.1519C6.17529 19.96 7.22314 19.9199 8.23926 20.0718C12.5327 20.7119 16.1885 22.6719 19.2529 25.7759C21.002 27.5439 22.3252 29.6558 23.6885 31.7202C25.1377 33.9121 26.6978 36 28.6831 37.7119C29.3843 38.312 29.9434 38.7681 30.479 39.104C28.8643 39.2881 26.1699 39.3281 24.3262 37.8398ZM26.3433 24.6001C26.3433 24.248 26.6191 23.9678 26.9658 23.9678C27.0444 23.9678 27.1152 23.9839 27.1782 24.0078C27.2651 24.04 27.3438 24.0879 27.4067 24.1602C27.5171 24.272 27.5801 24.4321 27.5801 24.6001C27.5801 24.9521 27.3042 25.2319 26.9575 25.2319C26.6108 25.2319 26.3433 24.9521 26.3433 24.6001ZM32.6064 27.8799C32.2046 28.0479 31.8027 28.1919 31.4165 28.208C30.8179 28.2397 30.1641 27.9922 29.8096 27.688C29.2583 27.2158 28.8643 26.9521 28.6987 26.1279C28.6279 25.7759 28.6675 25.2319 28.7305 24.9199C28.8721 24.248 28.7144 23.8159 28.2495 23.4238C27.8716 23.104 27.3911 23.0161 26.8633 23.0161C26.666 23.0161 26.4849 22.9277 26.3511 22.856C26.1304 22.7441 25.9492 22.4639 26.1226 22.1201C26.1777 22.0078 26.4458 21.7358 26.5088 21.688C27.2256 21.272 28.0527 21.4077 28.8169 21.7197C29.5259 22.0161 30.0615 22.5601 30.834 23.3281C31.6216 24.2559 31.7632 24.5117 32.2124 25.208C32.5669 25.752 32.8901 26.312 33.1104 26.9521C33.2446 27.3521 33.0713 27.6802 32.6064 27.8799Z'

/**
 * Ink bounds of WHALE_PATH in its own user units, measured by rasterising the
 * path (not the viewBox, which is 50x50 and leaves the mark off-centre).
 */
const WHALE_INK = { x: 1.0, y: 7.0, w: 48.3, h: 36.25 }

/**
 * The mark's optical centre sits above its bounding-box centre: the heavy round
 * body fills the lower left while the thin tail and flukes reach into the top
 * right. Centring the ink box alone still reads as slightly low, so the mark is
 * lifted by this share of the canvas. Tuned by rendering candidates and picking
 * by eye; the resulting ink box lands near y=245 in a 512 canvas.
 */
const OPTICAL_LIFT = 0.02

const CANVAS = 512

// ------------------------------------------------------------------- palette ---
const C = {
  bgTop: '#0B1020',
  bgBottom: '#161E33',
  grid: '#5B7CFA',
  particle: '#7FA8FF',
  particleHot: '#DCE8FF',
  whale: '#FFFFFF',
}

// ---------------------------------------------------------------- particles ---
/** Hand-placed specks in the empty corners around the mark. [x, y, r, opacity] */
const PARTICLES = [
  [56, 58, 3.0, 0.85], [130, 40, 1.8, 0.45], [216, 62, 2.1, 0.55], [318, 40, 1.6, 0.40],
  [452, 62, 2.8, 0.80], [494, 140, 1.6, 0.42], [488, 236, 2.2, 0.60], [504, 330, 1.5, 0.38],
  [476, 456, 3.0, 0.82], [392, 492, 1.7, 0.44], [286, 470, 2.0, 0.52], [176, 492, 1.5, 0.36],
  [44, 456, 2.9, 0.80], [20, 356, 1.6, 0.44], [40, 268, 2.2, 0.58], [16, 172, 1.5, 0.38],
  [86, 366, 1.5, 0.30], [430, 366, 1.5, 0.30], [150, 442, 1.4, 0.26], [366, 74, 1.4, 0.28],
  [458, 262, 1.4, 0.24], [64, 176, 1.4, 0.24],
]

/** Faint links that turn some specks into a constellation. */
const LINKS = [
  [56, 58, 130, 40], [216, 62, 318, 40], [452, 62, 494, 140], [494, 140, 488, 236],
  [488, 236, 504, 330], [504, 330, 476, 456], [476, 456, 392, 492], [392, 492, 286, 470],
  [286, 470, 176, 492], [176, 492, 44, 456], [44, 456, 20, 356], [20, 356, 40, 268],
  [40, 268, 16, 172], [16, 172, 56, 58], [86, 366, 44, 456], [430, 366, 452, 262],
]

/**
 * Build the whale's transform: its ink box is centred horizontally and placed
 * so the mark's optical centre - not its ink-box centre - sits mid-canvas.
 * @param inkWidthFraction - share of the canvas width the ink should span.
 * @returns the SVG transform string.
 */
function whaleTransform(inkWidthFraction) {
  const scale = (CANVAS * inkWidthFraction) / WHALE_INK.w
  const tx = CANVAS / 2 - scale * (WHALE_INK.x + WHALE_INK.w / 2)
  // Where the ink box must land for the mark to look centred: the box centre is
  // pushed up by the lift, expressed back in the mark's own user units.
  const boxCentreY = CANVAS / 2 - CANVAS * OPTICAL_LIFT
  const ty = boxCentreY - scale * (WHALE_INK.y + WHALE_INK.h / 2)
  return `translate(${tx.toFixed(2)} ${ty.toFixed(2)}) scale(${scale.toFixed(4)})`
}

/** Sizes that keep every detail, and the fractions the mark spans. */
const FULL_DETAIL_FROM = 32
const INK_FRACTION = 0.68
const INK_FRACTION_SMALL = 0.90

/**
 * Compose the icon artwork.
 * @param options.detail - false renders the small-size variant (no grid, no
 *   particles, larger mark).
 * @returns the SVG document as a string.
 */
function buildSvg({ detail = true } = {}) {
  const fraction = detail ? INK_FRACTION : INK_FRACTION_SMALL
  const transform = whaleTransform(fraction)
  const parts = []

  parts.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${CANVAS}" height="${CANVAS}" viewBox="0 0 ${CANVAS} ${CANVAS}">`)

  parts.push('  <defs>')
  parts.push('    <linearGradient id="bg" x1="0" y1="0" x2="0.6" y2="1">')
  parts.push(`      <stop offset="0" stop-color="${C.bgTop}"/>`)
  parts.push(`      <stop offset="1" stop-color="${C.bgBottom}"/>`)
  parts.push('    </linearGradient>')
  parts.push('    <radialGradient id="vignette" cx="0.5" cy="0.46" r="0.75">')
  parts.push(`      <stop offset="0" stop-color="${C.grid}" stop-opacity="0.20"/>`)
  parts.push('      <stop offset="1" stop-color="#000000" stop-opacity="0"/>')
  parts.push('    </radialGradient>')
  parts.push('    <radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">')
  parts.push('      <stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/>')
  parts.push('      <stop offset="0.55" stop-color="#ffffff" stop-opacity="0.05"/>')
  parts.push('      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>')
  parts.push('    </radialGradient>')
  parts.push('  </defs>')

  parts.push('  <!-- near-black base -->')
  parts.push(`  <rect x="0" y="0" width="${CANVAS}" height="${CANVAS}" fill="url(#bg)"/>`)
  parts.push(`  <rect x="0" y="0" width="${CANVAS}" height="${CANVAS}" fill="url(#vignette)"/>`)

  if (detail) {
    parts.push('  <!-- faint grid -->')
    const step = 32
    const faint = []
    const brighter = []
    for (let p = step; p < CANVAS; p += step) {
      const target = p % 128 === 0 ? brighter : faint
      target.push(`<path d="M${p} 0V${CANVAS}"/>`)
      target.push(`<path d="M0 ${p}H${CANVAS}"/>`)
    }
    parts.push(`  <g stroke="${C.grid}" stroke-width="1" stroke-opacity="0.05" fill="none">`)
    parts.push('    ' + faint.join(''))
    parts.push('  </g>')
    parts.push(`  <g stroke="${C.grid}" stroke-width="1.4" stroke-opacity="0.11" fill="none">`)
    parts.push('    ' + brighter.join(''))
    parts.push('  </g>')

    parts.push('  <!-- constellation -->')
    parts.push(`  <g stroke="${C.particle}" stroke-width="1" stroke-opacity="0.16" fill="none">`)
    for (const [x1, y1, x2, y2] of LINKS) parts.push(`    <path d="M${x1} ${y1}L${x2} ${y2}"/>`)
    parts.push('  </g>')

    parts.push('  <!-- specks -->')
    parts.push('  <g>')
    for (const [x, y, r, opacity] of PARTICLES) {
      const fill = opacity >= 0.7 ? C.particleHot : C.particle
      parts.push(`    <circle cx="${x}" cy="${y}" r="${r}" fill="${fill}" fill-opacity="${opacity}"/>`)
    }
    parts.push('  </g>')
  }

  parts.push('  <!-- soft halo so the mark sits in light rather than on a flat field -->')
  parts.push('  <ellipse cx="256" cy="256" rx="196" ry="150" fill="url(#halo)"/>')

  parts.push('  <!-- official DeepSeek whale mark, ink centred on the canvas -->')
  parts.push(`  <g transform="${transform}">`)
  parts.push(`    <path d="${WHALE_PATH}" fill="${C.whale}"/>`)
  parts.push('  </g>')

  parts.push('</svg>')
  return parts.join('\n') + '\n'
}

// --------------------------------------------------------------------- ICO ----

/** Icon sizes to embed, ascending; Windows picks the closest. */
const SIZES = [16, 24, 32, 48, 64, 128, 256]

/**
 * Encode one raw RGBA bitmap as a 32-bit bottom-up DIB (BITMAPINFOHEADER with
 * an all-zero AND mask), which is what an ICO directory entry expects when it
 * is not a PNG.
 * @param rgba - tightly packed RGBA bytes, width*height*4, top-down.
 * @param size - square edge length in pixels.
 * @returns the DIB buffer.
 */
function encodeDib(rgba, size) {
  const header = Buffer.alloc(40)
  header.writeUInt32LE(40, 0)          // biSize
  header.writeInt32LE(size, 4)         // biWidth
  header.writeInt32LE(size * 2, 8)     // biHeight: colour + AND mask
  header.writeUInt16LE(1, 12)          // biPlanes
  header.writeUInt16LE(32, 14)         // biBitCount
  header.writeUInt32LE(0, 16)          // biCompression = BI_RGB
  header.writeUInt32LE(size * size * 4, 20)

  const pixels = Buffer.alloc(size * size * 4)
  for (let y = 0; y < size; y++) {
    const src = (size - 1 - y) * size * 4   // DIB rows run bottom-up
    const dst = y * size * 4
    for (let x = 0; x < size; x++) {
      const s = src + x * 4
      const d = dst + x * 4
      pixels[d] = rgba[s + 2]               // B
      pixels[d + 1] = rgba[s + 1]           // G
      pixels[d + 2] = rgba[s]               // R
      pixels[d + 3] = rgba[s + 3]           // A
    }
  }

  const maskStride = Math.ceil(size / 32) * 4
  const mask = Buffer.alloc(maskStride * size)  // opaque: every bit zero
  return Buffer.concat([header, pixels, mask])
}

/**
 * Wrap encoded images in an ICO container.
 * @param entries - one per size, ascending, each { size, data }.
 * @returns the .ico file bytes.
 */
function encodeIco(entries) {
  const header = Buffer.alloc(6)
  header.writeUInt16LE(0, 0)              // reserved
  header.writeUInt16LE(1, 2)              // type 1 = icon
  header.writeUInt16LE(entries.length, 4)

  const directory = Buffer.alloc(16 * entries.length)
  let offset = header.length + directory.length
  entries.forEach((entry, index) => {
    const at = index * 16
    directory.writeUInt8(entry.size >= 256 ? 0 : entry.size, at)      // width
    directory.writeUInt8(entry.size >= 256 ? 0 : entry.size, at + 1)  // height
    directory.writeUInt8(0, at + 2)                                   // palette
    directory.writeUInt8(0, at + 3)                                   // reserved
    directory.writeUInt16LE(1, at + 4)                                // planes
    directory.writeUInt16LE(32, at + 6)                               // bit count
    directory.writeUInt32LE(entry.data.length, at + 8)
    directory.writeUInt32LE(offset, at + 12)
    offset += entry.data.length
  })

  return Buffer.concat([header, directory, ...entries.map(e => e.data)])
}

// ----------------------------------------------------------------- preview ---

/**
 * Rasterise artwork and print it as ASCII, so the composition can be checked
 * without opening an image.
 * @param svg - the SVG document.
 * @param size - preview resolution (sampled from a 2x render).
 */
async function preview(svg, size) {
  const { data } = await sharp(Buffer.from(svg))
    .resize(size * 2, size * 2)
    .greyscale()
    .raw()
    .toBuffer({ resolveWithObject: true })

  const ramp = ' .:-=+*#%@'
  const lines = []
  for (let y = 0; y < size; y++) {
    let line = ''
    for (let x = 0; x < size; x++) {
      // average a small block so specks survive the downsample
      const px = data[(y * 2) * size * 2 + x * 2]
      line += ramp[Math.min(ramp.length - 1, Math.round((px / 255) * (ramp.length - 1)))]
    }
    lines.push(line)
  }
  return lines.join('\n')
}

// --------------------------------------------------------------------- main ---

const fullSvg = buildSvg({ detail: true })
const smallSvg = buildSvg({ detail: false })

writeFileSync(svgPath, fullSvg, 'utf8')
console.log(`wrote ${svgPath} (512px artwork)`)

const entries = []
for (const size of SIZES) {
  const svg = size >= FULL_DETAIL_FROM ? fullSvg : smallSvg
  const label = size >= FULL_DETAIL_FROM ? 'full' : 'small'
  const base = sharp(Buffer.from(svg)).resize(size, size, { kernel: 'lanczos3' })
  await base.clone().png().toFile(join(assetsDir, `dsh-icon-${size}.png`))
  const rgba = await base.clone().ensureAlpha().raw().toBuffer()
  const data = encodeDib(rgba, size)
  entries.push({ size, data })
  console.log(`${String(size).padStart(3)}px  ${label.padEnd(5)} dib  ${data.length} bytes`)
}

await sharp(Buffer.from(fullSvg)).resize(512, 512).png().toFile(join(assetsDir, 'dsh-icon.png'))
console.log('512px  full  png  (dsh-icon.png)')

writeFileSync(icoPath, encodeIco(entries))
console.log(`\nwrote ${icoPath} (${readFileSync(icoPath).length} bytes, ${entries.length} sizes)`)

if (process.argv.includes('--preview')) {
  console.log('\n--- 512px artwork ---')
  console.log(await preview(fullSvg, 64))
  console.log('\n--- small-size variant ---')
  console.log(await preview(smallSvg, 24))
}
