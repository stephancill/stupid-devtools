// The subset of the WebExtension `browser` API these scripts use.
type Tab = { id?: number; url?: string }
type MessageSender = { tab?: Tab }

declare const browser: {
  runtime: {
    sendMessage(message: unknown): Promise<unknown>
    sendNativeMessage(application: string, message: unknown): Promise<unknown>
    onMessage: {
      addListener(listener: (message: unknown, sender: MessageSender) => unknown): void
      removeListener(listener: (message: unknown, sender: MessageSender) => unknown): void
    }
  }
  tabs: {
    query(options: { active?: boolean; currentWindow?: boolean }): Promise<Tab[]>
    sendMessage(tabId: number, message: unknown): Promise<unknown>
    onRemoved: { addListener(listener: (tabId: number) => void): void }
  }
}
