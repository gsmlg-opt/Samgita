interface MergeDialogHook {
  el: HTMLDialogElement
  events: AbortController
}

export const GitHubMergeDialog = {
  mounted(this: MergeDialogHook) {
    const dialog = this.el
    this.events = new AbortController()
    const { signal } = this.events

    dialog.addEventListener("beforetoggle", (event: ToggleEvent) => {
      if (event.newState === "open") dialog.querySelector("form")?.reset()
    }, { signal })

    // LiveView handles the valid form submission and prevents the native dialog close.
    dialog.addEventListener("submit", () => dialog.close(), { signal })
  },
  destroyed(this: MergeDialogHook) { this.events.abort() },
}
