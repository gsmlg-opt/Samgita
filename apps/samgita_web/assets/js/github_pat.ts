async function submit(path: string, payload: object, signal: AbortSignal) {
  const csrf = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")!.content
  const response = await fetch(path, {
    method: "POST",
    credentials: "same-origin",
    signal,
    headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
    body: JSON.stringify(payload),
  })
  if (!response.headers.get("content-type")?.includes("application/json")) {
    throw new Error("Reload Settings and try saving the PAT again.")
  }
  const result = await response.json()
  if (!response.ok) throw new Error(result.error || "Could not save the GitHub connection.")
  return result
}

async function save(token: string, version: string, signal: AbortSignal) {
  if (!token) throw new Error("Paste the full GitHub token value.")
  const { ticket, public_key } = await submit("/settings/github/pat/challenge", { version }, signal)
  const { encryptPat } = await import("./github_pat_envelope")
  const envelope = encryptPat(token, public_key, ticket)
  await submit("/settings/github/pat", { ticket, ...envelope }, signal)
}

interface Hook {
  el: HTMLFormElement
  events: AbortController
}

export const GitHubPAT = {
  mounted(this: Hook) {
    const form = this.el
    const input = form.querySelector<HTMLInputElement>("[data-pat-input]")!
    const button = form.querySelector<HTMLButtonElement>("button[type=submit]")!
    const error = form.querySelector<HTMLElement>("[data-pat-error]")!
    this.events = new AbortController()
    const { signal } = this.events
    form.addEventListener("submit", async event => {
      event.preventDefault()
      if (button.disabled) return
      button.disabled = true
      input.readOnly = true
      error.textContent = ""
      try {
        await save(input.value.trim(), form.dataset.version || "", signal)
        if (!signal.aborted) {
          input.value = ""
          window.location.assign("/settings?section=github")
        }
      } catch (reason) {
        if (!signal.aborted) {
          error.textContent = reason instanceof Error ? reason.message : "Could not save the GitHub connection."
        }
      } finally {
        input.readOnly = false
        button.disabled = false
      }
    }, { signal })
  },
  destroyed(this: Hook) { this.events.abort() },
}
