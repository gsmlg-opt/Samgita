// Codex session chat: the DuskMoon React chat with the public composition API
// (phoenix_duskmoon guides/react-chat.md). The default hook composer is a
// single-line input; Chat.Composer is the multi-line composer of the DuskMoon
// chat demo (Enter sends, Shift+Enter inserts a newline, Stop while working).
import React, { useState } from "react"
import { Chat } from "@duskmoon-dev/components/chat"
import { Markdown } from "@duskmoon-dev/components/markdown"
import { createDuskmoonReactChat, useChatSubmission } from "phoenix_duskmoon/react-chat"

const h = React.createElement

// Drafts survive a remount of the same conversation (for example a reconnect).
const drafts = new Map()

function Composer(props) {
  const id = props.state.conversationId
  const [value, setValue] = useState(() => drafts.get(id) || "")
  const [error, setError] = useState()
  const { submit, busy, notice } = useChatSubmission(props)

  function update(next) {
    drafts.set(id, next)
    setValue(next)
  }

  return h(Chat.Composer, {
    value,
    onValueChange: update,
    // While Codex works the message joins the running turn (server: turn/steer).
    generating: props.active,
    canSubmit: props.canSubmit,
    busy,
    error: error || notice || undefined,
    minRows: 2,
    maxRows: 12,
    sendLabel: "Send",
    stopLabel: "Stop",
    textareaProps: {
      "aria-label": "Message to Codex",
      placeholder: props.active ? "Add to what Codex is doing…" : "Ask Codex to do something…",
    },
    onStop: () => props.bridge.send("stop", {}).catch((e) => setError(e.message)),
    onSubmit: async ({ value }) => {
      setError(undefined)
      try {
        await submit({ text: value })
        drafts.delete(id)
        return true
      } catch {
        // useChatSubmission keeps the rejection in `notice`; the draft stays.
        return false
      }
    },
  })
}

function ToolBody({ tool }) {
  const result = tool.result
  if (tool.kind === "command")
    return h(
      Chat.ToolResult,
      null,
      result?.exit_code != null && h("p", null, `exit ${result.exit_code}`),
      result?.output && h("pre", { className: "max-h-80 overflow-auto whitespace-pre-wrap" }, result.output),
    )
  if (tool.kind === "file_change")
    return h(
      Chat.ToolResult,
      null,
      ...(tool.paths || []).map((path) => h("code", { key: path, className: "block break-all" }, path)),
    )
  return null
}

function Work({ tools }) {
  return h(
    Chat.Work,
    null,
    h(Chat.WorkSummary, null, tools.length === 1 ? "Worked · 1 step" : `Worked · ${tools.length} steps`),
    h(
      Chat.WorkBody,
      null,
      ...tools.map((tool) =>
        tool.kind === "reasoning" || tool.kind === "plan"
          ? h(
              Chat.Reasoning,
              { key: tool.id },
              h("summary", null, tool.name),
              h(Markdown, { markdown: tool.text || "" }),
            )
          : h(
              Chat.Tool,
              { key: tool.id, status: tool.status },
              h(Chat.ToolHeader, null, tool.name, h(Chat.ToolStatus, null, tool.status)),
              h(ToolBody, { tool }),
            ),
      ),
    ),
  )
}

function Message({ message, targetId, timeline }) {
  const streaming = message.status === "streaming"

  if (message.role !== "assistant")
    return h(
      Chat,
      { id: targetId, role: "article", placement: "end", "data-message-id": message.id },
      h(Chat.Header, null, message.author || "You"),
      h(
        Chat.Bubble,
        { collapsible: true },
        h(Markdown, { markdown: message.content || "", className: "chat-bubble-content" }),
      ),
    )

  const tools = message.tools || []
  return h(
    Chat.Agent,
    { id: targetId, timeline, role: "article", "data-message-id": message.id },
    h(Chat.Header, null, message.author || "Codex"),
    tools.length > 0 && h(Work, { tools }),
    message.content
      ? h(Chat.Content, { streaming }, h(Markdown, { markdown: message.content }))
      : streaming && h(Chat.Typing, { "aria-label": "Codex is working" }),
  )
}

export const SessionChat = createDuskmoonReactChat({ Composer, renderMessage: Message })
