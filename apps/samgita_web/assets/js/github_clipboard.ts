function legacyCopy(text: string): boolean {
  const active = document.activeElement instanceof HTMLElement ? document.activeElement : null
  const selection = window.getSelection()
  const ranges = selection ? Array.from({ length: selection.rangeCount }, (_, index) => selection.getRangeAt(index).cloneRange()) : []
  const input = document.createElement("textarea")
  input.value = text
  input.readOnly = true
  input.style.position = "fixed"
  input.style.opacity = "0"
  input.style.left = "0"
  input.style.top = "0"
  document.body.append(input)

  try {
    input.focus()
    input.select()
    return document.execCommand("copy")
  } catch {
    return false
  } finally {
    input.remove()
    active?.focus({ preventScroll: true })
    selection?.removeAllRanges()
    for (const range of ranges) selection?.addRange(range)
  }
}

interface ClipboardHook {
  el: HTMLButtonElement
  events: AbortController
}

export const GitHubClipboard = {
  mounted(this: ClipboardHook) {
    this.events = new AbortController()

    this.el.addEventListener("click", async () => {
      const text = this.el.dataset.copyText || ""
      let copied = false

      if (navigator.clipboard?.writeText) {
        try {
          await navigator.clipboard.writeText(text)
          copied = true
        } catch {
          copied = legacyCopy(text)
        }
      } else {
        copied = legacyCopy(text)
      }

      if (this.events.signal.aborted) return
      const feedback = document.getElementById(this.el.dataset.feedbackId || "")
      if (feedback) feedback.textContent = copied ? this.el.dataset.copySuccess || "Link copied." : this.el.dataset.copyError || "Could not copy this link."
    }, { signal: this.events.signal })
  },
  destroyed(this: ClipboardHook) { this.events.abort() },
}
