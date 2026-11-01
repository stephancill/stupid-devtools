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
    if (url.pathname === "/demo") return new Response(Bun.file(`${import.meta.dir}/demo.html`))
    if (url.pathname === "/demo/api/products") {
      return Response.json({
        items: [
          { id: "ethiopia-yirgacheffe", name: "Ethiopia Yirgacheffe", price: 185, roast: "light" },
          { id: "colombia-huila", name: "Colombia Huila", price: 165, roast: "medium" },
          { id: "sumatra-mandheling", name: "Sumatra Mandheling", price: 175, roast: "dark" },
          { id: "house-espresso", name: "House Espresso", price: 150, roast: "medium-dark" },
        ],
        total: 4,
        nextCursor: null,
      })
    }
    if (url.pathname === "/demo/api/session") {
      return Response.json({
        user: { id: "u_8f3k2", name: "Sam", tier: "member" },
        expiresIn: 3600,
      })
    }
    if (url.pathname === "/demo/api/cart") {
      return Response.json(
        { cartId: "c_19x7", items: 1, subtotal: 370, currency: "ZAR" },
        { status: 201 },
      )
    }
    if (url.pathname === "/demo/api/recommendations") {
      return Response.json({ error: "Service Unavailable" }, { status: 503 })
    }
    if (url.pathname === "/demo/api/stores") {
      return Response.json([
        { name: "Roast Bree St", open: true },
        { name: "Roast Kloof St", open: false },
      ])
    }
    if (url.pathname === "/demo/api/analytics") return new Response(null, { status: 204 })
    if (url.pathname === "/api/xml") {
      const xml =
        '<?xml version="1.0"?><feed><item id="1"><title>One</title></item><item id="2"/></feed>'
      return new Response(xml, { headers: { "content-type": "application/xml" } })
    }
    if (url.pathname === "/api/form") {
      return new Response("name=stupid+devtools&tags=a&tags=b%26c", {
        headers: { "content-type": "application/x-www-form-urlencoded" },
      })
    }
    if (url.pathname === "/api/html") {
      return new Response("<!doctype html><h1>Hello</h1>", {
        headers: { "content-type": "text/html" },
      })
    }
    if (url.pathname === "/api/image") {
      return new Response(
        Bun.file(`${import.meta.dir}/../../SafariExtension/Resources/icon-96.png`),
      )
    }
    if (url.pathname === "/api/untyped") return new Response('{"sniffed":true}')
    const status = url.pathname.match(/^\/api\/status\/(\d+)$/)
    if (status) return new Response("status page", { status: Number(status[1]) })
    return new Response("not found", { status: 404 })
  },
})
console.log(`Test page on http://localhost:${port}`)
