import { describe, expect, test } from "bun:test"
import { formatConsoleArgs, formatValueForDisplay } from "./format"

describe("formatValueForDisplay", () => {
  test("keeps values JSON drops", () => {
    expect(formatValueForDisplay(undefined)).toBe("undefined")
    expect(formatValueForDisplay(10n)).toBe("10n")
    expect(formatValueForDisplay({ a: undefined, f() {} })).toBe(
      "{\n  a: undefined,\n  f: ƒ f()\n}",
    )
  })

  test("marks circular references", () => {
    const value: Record<string, unknown> = { name: "loop" }
    value.self = value
    expect(formatValueForDisplay(value)).toBe('{\n  name: "loop",\n  self: [Circular]\n}')
  })

  test("reports getters that throw", () => {
    const value = {
      get broken() {
        throw new Error("nope")
      },
    }
    expect(formatValueForDisplay(value)).toContain("[getter threw: Error: nope]")
  })
})

describe("formatConsoleArgs", () => {
  test("applies substitutions and drops %c styles", () => {
    expect(formatConsoleArgs(["%s is %d%c!", "x", 4.5, "color: red", "extra"])).toBe(
      "x is 4! extra",
    )
  })

  test("joins plain arguments", () => {
    expect(formatConsoleArgs(["count", 3, [1, 2]])).toBe("count 3 [\n  1,\n  2\n]")
  })
})
