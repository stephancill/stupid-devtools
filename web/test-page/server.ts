// Serves the test page for manual and simulator testing: `bun run test-page/server.ts`.
const port = Number(process.env.PORT ?? 5177)

Bun.serve({
  port,
  hostname: "0.0.0.0",
  async fetch(request) {
    const url = new URL(request.url)
    if (url.pathname === "/") return new Response(Bun.file(`${import.meta.dir}/index.html`))
    if (url.pathname.startsWith("/api/json")) {
      return Response.json({ ok: true, query: Object.fromEntries(url.searchParams) })
    }
    if (url.pathname === "/api/echo") {
      return Response.json({ method: request.method, body: await request.text() })
    }
    const status = url.pathname.match(/^\/api\/status\/(\d+)$/)
    if (status) return new Response("status page", { status: Number(status[1]) })
    return new Response("not found", { status: 404 })
  },
})
console.log(`Test page on http://localhost:${port}`)
