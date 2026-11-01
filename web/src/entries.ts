// Entry shapes shared by every script. The Swift side decodes the same JSON
// (Sources/DevToolsCore/Entry.swift), so keep the two in sync.
// zod/mini keeps content.js small; it is injected into every page.
import * as z from "zod/mini"

export const logLevels = ["log", "info", "warn", "error", "debug", "command", "result"] as const

const headers = z.record(z.string(), z.string())

export const logEntrySchema = z.object({
  kind: z.literal("log"),
  id: z.string(),
  level: z.enum(logLevels),
  message: z.string(),
  time: z.number(),
})

export const requestBodySchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("text"), text: z.string() }),
  z.object({
    kind: z.literal("form"),
    fields: z.array(
      z.object({
        name: z.string(),
        value: z.optional(z.string()),
        fileName: z.optional(z.string()),
      }),
    ),
  }),
  z.object({ kind: z.literal("binary"), byteLength: z.optional(z.number()) }),
])

export const requestEntrySchema = z.object({
  kind: z.literal("request"),
  id: z.string(),
  initiator: z.enum(["fetch", "xhr"]),
  method: z.string(),
  url: z.string(),
  requestHeaders: headers,
  requestBody: z.optional(requestBodySchema),
  // document.cookie at send time, only for same-origin requests. Excludes HttpOnly cookies.
  cookies: z.optional(z.string()),
  status: z.optional(z.number()),
  statusText: z.optional(z.string()),
  responseHeaders: z.optional(headers),
  responseBody: z.optional(z.string()),
  responseBodyTruncated: z.optional(z.boolean()),
  error: z.optional(z.string()),
  startTime: z.number(),
  endTime: z.optional(z.number()),
})

export const entrySchema = z.discriminatedUnion("kind", [logEntrySchema, requestEntrySchema])

export type LogEntry = z.infer<typeof logEntrySchema>
export type LogLevel = LogEntry["level"]
export type RequestBody = z.infer<typeof requestBodySchema>
export type RequestEntry = z.infer<typeof requestEntrySchema>
export type Entry = z.infer<typeof entrySchema>
