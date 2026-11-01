// Turns console arguments into display strings without throwing, recursing forever
// or losing values that JSON would drop (undefined, functions, symbols, bigint).

const maxDepth = 4
const maxItems = 100

const formatValue = (value: unknown, depth: number, seen: WeakSet<object>): string => {
  switch (typeof value) {
    case "string":
      return depth === 0 ? value : JSON.stringify(value)
    case "number":
    case "boolean":
    case "undefined":
      return String(value)
    case "bigint":
      return `${value}n`
    case "symbol":
      return value.toString()
    case "function":
      return `ƒ ${value.name || "anonymous"}()`
  }
  if (value === null) return "null"
  const object = value as object

  if (object instanceof Error) {
    return object.stack?.includes(object.message)
      ? object.stack
      : `${object.name}: ${object.message}${object.stack ? `\n${object.stack}` : ""}`
  }
  if (typeof Node !== "undefined" && object instanceof Node) return describeNode(object)
  if (object instanceof Date) return object.toISOString()
  if (object instanceof RegExp) return object.toString()
  if (seen.has(object)) return "[Circular]"
  if (depth >= maxDepth) return Array.isArray(object) ? "[…]" : "{…}"

  seen.add(object)
  try {
    const child = (v: unknown) => formatValue(v, depth + 1, seen)
    const indent = "  ".repeat(depth + 1)
    const close = "  ".repeat(depth)
    const block = (open: string, items: string[], end: string, total: number) => {
      if (items.length === 0) return `${open}${end}`
      if (total > items.length) items.push(`… ${total - items.length} more`)
      return `${open}\n${items.map((item) => indent + item).join(",\n")}\n${close}${end}`
    }

    if (Array.isArray(object)) {
      return block("[", object.slice(0, maxItems).map(child), "]", object.length)
    }
    if (object instanceof Map) {
      const items = [...object].slice(0, maxItems).map(([k, v]) => `${child(k)} => ${child(v)}`)
      return block(`Map(${object.size}) {`, items, "}", object.size)
    }
    if (object instanceof Set) {
      return block(
        `Set(${object.size}) {`,
        [...object].slice(0, maxItems).map(child),
        "}",
        object.size,
      )
    }
    if (ArrayBuffer.isView(object) || object instanceof ArrayBuffer) {
      return `${object.constructor.name}(${object.byteLength})`
    }

    const keys = Object.keys(object)
    const name =
      object.constructor && object.constructor !== Object ? `${object.constructor.name} ` : ""
    const items = keys.slice(0, maxItems).map((key) => {
      let property: unknown
      try {
        property = (object as Record<string, unknown>)[key]
      } catch (error) {
        property = `[getter threw: ${String(error)}]`
      }
      return `${/^[A-Za-z_$][\w$]*$/.test(key) ? key : JSON.stringify(key)}: ${child(property)}`
    })
    return block(`${name}{`, items, "}", keys.length)
  } finally {
    seen.delete(object)
  }
}

const describeNode = (node: Node): string => {
  if (node instanceof Element) {
    const id = node.id ? `#${node.id}` : ""
    const classes = [...node.classList].map((c) => `.${c}`).join("")
    return `<${node.tagName.toLowerCase()}${id}${classes}>`
  }
  if (node.nodeType === Node.TEXT_NODE) return `#text ${JSON.stringify(node.textContent)}`
  return node.nodeName
}

export const formatValueForDisplay = (value: unknown) => formatValue(value, 0, new WeakSet())

// Applies printf-style substitutions (%s %d %i %f %o %O %c) like browser consoles do.
export const formatConsoleArgs = (args: unknown[]): string => {
  const rest = [...args]
  const parts: string[] = []
  const first = rest[0]
  if (typeof first === "string" && first.includes("%") && rest.length > 1) {
    rest.shift()
    parts.push(
      first.replace(/%([sdifoOc%])/g, (match, token: string) => {
        if (token === "%") return "%"
        if (rest.length === 0) return match
        const arg = rest.shift()
        switch (token) {
          case "s":
            return typeof arg === "string" ? arg : formatValueForDisplay(arg)
          case "d":
          case "i":
            return String(Number.parseInt(String(arg), 10))
          case "f":
            return String(Number.parseFloat(String(arg)))
          case "c":
            return ""
          default:
            return formatValue(arg, 1, new WeakSet())
        }
      }),
    )
  }
  return [...parts, ...rest.map(formatValueForDisplay)].join(" ")
}
