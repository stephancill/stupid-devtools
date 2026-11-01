// Builds the Safari extension scripts into ../SafariExtension/Resources, next to the
// hand-written manifest and icons.
import { copyFile } from "node:fs/promises"
import { join } from "node:path"

const outdir = join(import.meta.dir, "../SafariExtension/Resources")

const build = async (entry: string, format: "iife" | "esm") => {
  const result = await Bun.build({
    entrypoints: [join(import.meta.dir, entry)],
    outdir,
    format,
    target: "browser",
    minify: true,
    define: { "process.env.NODE_ENV": '"production"' },
  })
  if (!result.success) {
    for (const log of result.logs) console.error(log)
    throw new Error(`Build failed: ${entry}`)
  }
}

// Content scripts and the background script must be classic scripts.
await build("src/page.ts", "iife")
await build("src/content.ts", "iife")
await build("src/background.ts", "iife")
await build("src/popup/popup.tsx", "esm")
await copyFile(join(import.meta.dir, "src/popup/popup.html"), join(outdir, "popup.html"))
await copyFile(join(import.meta.dir, "src/popup/popup.css"), join(outdir, "popup.css"))
console.log(`Built extension scripts into ${outdir}`)
