// Codex session chat: the DuskMoon React chat with the public composition API
// (phoenix_duskmoon guides/react-chat.md). The default hook composer is a
// single-line input; Chat.Composer is the multi-line composer of the DuskMoon
// chat demo (Enter sends, Shift+Enter inserts a newline, Stop while working).
import React, { useState } from "react"
import { Chat } from "@duskmoon-dev/components/chat"
import { Markdown } from "@duskmoon-dev/components/markdown"
import { createDuskmoonReactChat, useChatSubmission } from "phoenix_duskmoon/react-chat"

const h = React.createElement

// Material Design Icons paths (the set phoenix_duskmoon's dm_mdi serves).
const icons = {
  down: "M7.41,8.58L12,13.17L16.59,8.58L18,10L12,16L6,10L7.41,8.58Z",
  right: "M8.59,16.58L13.17,12L8.59,7.41L10,6L16,12L10,18L8.59,16.58Z",
  check: "M21,7L9,19L3.5,13.5L4.91,12.09L9,16.17L19.59,5.59L21,7Z",
  reset:
    "M13,3A9,9 0 0,0 4,12H1L4.89,15.89L4.96,16.03L9,12H6A7,7 0 0,1 13,5A7,7 0 0,1 20,12A7,7 0 0,1 13,19C11.07,19 9.32,18.21 8.06,16.94L6.64,18.36C8.27,20 10.5,21 13,21A9,9 0 0,0 22,12A9,9 0 0,0 13,3Z",
  folder:
    "M20,18H4V8H20M20,6H12L10,4H4C2.89,4 2,4.89 2,6V18A2,2 0 0,0 4,20H20A2,2 0 0,0 22,18V8C22,6.89 21.1,6 20,6Z",
  web: "M16.36,14C16.44,13.34 16.5,12.68 16.5,12C16.5,11.32 16.44,10.66 16.36,10H19.74C19.9,10.64 20,11.31 20,12C20,12.69 19.9,13.36 19.74,14M14.59,19.56C15.19,18.45 15.65,17.25 15.97,16H18.92C17.96,17.65 16.43,18.93 14.59,19.56M14.34,14H9.66C9.56,13.34 9.5,12.68 9.5,12C9.5,11.32 9.56,10.65 9.66,10H14.34C14.43,10.65 14.5,11.32 14.5,12C14.5,12.68 14.43,13.34 14.34,14M12,19.96C11.17,18.76 10.5,17.43 10.09,16H13.91C13.5,17.43 12.83,18.76 12,19.96M8,8H5.08C6.03,6.34 7.57,5.06 9.4,4.44C8.8,5.55 8.35,6.75 8,8M5.08,16H8C8.35,17.25 8.8,18.45 9.4,19.56C7.57,18.93 6.03,17.65 5.08,16M4.26,14C4.1,13.36 4,12.69 4,12C4,11.31 4.1,10.64 4.26,10H7.64C7.56,10.66 7.5,11.32 7.5,12C7.5,12.68 7.56,13.34 7.64,14M12,4.03C12.83,5.23 13.5,6.57 13.91,8H10.09C10.5,6.57 11.17,5.23 12,4.03M18.92,8H15.97C15.65,6.75 15.19,5.55 14.59,4.44C16.43,5.07 17.96,6.34 18.92,8M12,2C6.47,2 2,6.5 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2Z",
  laptop:
    "M4,6H20V16H4M20,18A2,2 0 0,0 22,16V6C22,4.89 21.1,4 20,4H4C2.89,4 2,4.89 2,6V16A2,2 0 0,0 4,18H0V20H24V18H20Z",
  shieldAlert:
    "M21,11C21,16.55 17.16,21.74 12,23C6.84,21.74 3,16.55 3,11V5L12,1L21,5V11M12,21C15.75,20 19,15.54 19,11.22V6.3L12,3.18L5,6.3V11.22C5,15.54 8.25,20 12,21M11,7H13V13H11V7M11,15H13V17H11V15Z",
  shieldCheck:
    "M21,11C21,16.55 17.16,21.74 12,23C6.84,21.74 3,16.55 3,11V5L12,1L21,5V11M12,21C15.75,20 19,15.54 19,11.22V6.3L12,3.18L5,6.3V11.22C5,15.54 8.25,20 12,21M10,17L6,13L7.41,11.59L10,14.17L16.59,7.58L18,9",
}

const Icon = ({ path }) =>
  h("svg", { viewBox: "0 0 24 24", width: 16, height: 16, fill: "currentColor", "aria-hidden": true }, h("path", { d: path }))

// Where this session runs, as in the Codex app: project, local or remote, and
// the host with its connection status.
function Context({ metadata }) {
  const { project, location, host, connected } = metadata
  return h(
    "div",
    {
      "data-session-context": true,
      className:
        "mx-4 flex items-center gap-5 rounded-t-[1.25rem] bg-surface-container px-5 py-2 text-sm text-on-surface-variant",
    },
    project && h("span", { className: "flex items-center gap-2" }, h(Icon, { path: icons.folder }), project),
    h(
      "span",
      { className: "flex items-center gap-2" },
      h(Icon, { path: location === "Local" ? icons.laptop : icons.web }),
      location,
    ),
    host &&
      h(
        "span",
        { className: "ms-auto flex items-center gap-2", title: connected ? "Connected" : "Not connected" },
        host,
        h("span", {
          "aria-label": connected ? "Connected" : "Not connected",
          className: `inline-block h-2 w-2 rounded-full ${connected ? "bg-success" : "bg-outline"}`,
        }),
      ),
  )
}

// Access, model and reasoning effort for the next message, built like the
// DuskMoon chat composer demo (core chat-composer-menu classes, native popovers
// anchored to their triggers). The server checks each choice (`chat.setting`)
// and pushes the new values back in `metadata`; they apply to the next turn.
const ACCESS_HELP = {
  read_only: "Codex can read files but not change them.",
  default: "Edits in this project; asks before anything else.",
  full: "Runs any command without asking. Use with care.",
}

const capitalize = (text) => (text ? text[0].toUpperCase() + text.slice(1) : "")

// Moves locally while dragging; sends the effort once released.
function EffortSlider({ efforts, value, onCommit }) {
  const [index, setIndex] = useState(value)
  const commit = () => onCommit(efforts[index])
  return h(
    "div",
    { className: "chat-composer-menu-field" },
    h("input", {
      className: "range range-sm",
      type: "range",
      min: 0,
      max: efforts.length - 1,
      step: 1,
      value: index,
      "aria-label": "Reasoning effort",
      "aria-valuetext": capitalize(efforts[index]),
      onChange: (event) => setIndex(Number(event.target.value)),
      onPointerUp: commit,
      onKeyUp: commit,
    }),
  )
}

function Settings({ metadata, bridge, conversationId }) {
  const [notice, setNotice] = useState("")
  const settings = Object.fromEntries((metadata.settings || []).map((setting) => [setting.id, setting]))
  const { access, model, effort } = settings
  if (!access || !model || !effort) return null

  const base = `session-${conversationId}`.replace(/[^A-Za-z0-9_-]/g, "")
  const label = (setting) => setting.choices.find((c) => c.value === setting.value)?.label || setting.value
  const close = (id) => document.getElementById(id)?.hidePopover?.()

  async function choose(settingId, value, menu) {
    close(menu)
    setNotice("")
    try {
      await bridge.send("setting", { settingId, value })
    } catch (error) {
      setNotice(error.message)
    }
  }

  const efforts = effort.choices.map((c) => c.value)
  const effortIndex = Math.max(0, efforts.indexOf(effort.value))
  const full = access.value === "full"

  const option = (settingId, choice, current, menu, description, warning) =>
    h(
      "button",
      {
        key: choice.value,
        type: "button",
        className: `popover-menu-item chat-composer-menu-option${warning ? " chat-composer-menu-option-warning" : ""}`,
        "aria-pressed": choice.value === current,
        onClick: () => choose(settingId, choice.value, menu),
      },
      settingId === "access" && h("span", { className: "popover-menu-item-icon" }, h(Icon, { path: icons.shieldCheck })),
      h(
        "span",
        { className: "chat-composer-label" },
        choice.label,
        description && h("span", { className: "chat-composer-description" }, description),
      ),
      choice.value === current && h(Icon, { path: icons.check }),
    )

  return h(
    React.Fragment,
    null,
    // Access: shield trigger with the current mode, and its menu.
    h(
      "button",
      {
        type: "button",
        className: `btn btn-ghost btn-sm${full ? " text-warning" : ""}`,
        "aria-label": `Access: ${label(access)}`,
        "data-session-access": true,
        popoverTarget: `${base}-access`,
        style: { anchorName: `--${base}-access` },
      },
      h(Icon, { path: full ? icons.shieldAlert : icons.shieldCheck }),
      h("span", null, label(access)),
    ),
    h(
      "div",
      {
        id: `${base}-access`,
        popover: "auto",
        className: "popover popover-menu chat-composer-menu",
        "aria-label": "Access",
        style: { positionAnchor: `--${base}-access` },
      },
      h("div", { className: "chat-composer-group" }, "Access"),
      ...access.choices.map((choice) =>
        option("access", choice, access.value, `${base}-access`, ACCESS_HELP[choice.value], choice.value === "full"),
      ),
    ),
    metadata.pending &&
      h("span", { "data-session-pending": true, className: "text-xs text-on-surface-variant" }, "Applies to your next message"),
    notice && h("span", { role: "alert", className: "text-xs text-error" }, notice),
    // Model and reasoning: one trigger "Model Effort", a panel and a model list.
    h(
      "div",
      { className: "chat-composer-actions ms-auto" },
      h(
        "button",
        {
          type: "button",
          className: "btn btn-ghost btn-sm chat-composer-config",
          "aria-label": `Model and reasoning: ${label(model)}, ${capitalize(effort.value)}`,
          "data-session-model": true,
          popoverTarget: `${base}-config`,
          style: { anchorName: `--${base}-config` },
        },
        h("span", { className: "chat-composer-label" }, `${label(model)} `, h("span", { className: "text-on-surface-variant" }, capitalize(effort.value))),
        h(Icon, { path: icons.down }),
      ),
    ),
    h(
      "div",
      {
        id: `${base}-config`,
        popover: "auto",
        className: "popover popover-menu chat-composer-menu chat-composer-menu-end",
        "aria-label": "Model and reasoning",
        style: { positionAnchor: `--${base}-config` },
      },
      h(
        "div",
        { className: "chat-composer-menu-row" },
        h("strong", null, capitalize(effort.value)),
        effort.default &&
          h(
            "button",
            {
              type: "button",
              className: "btn btn-ghost btn-xs btn-circle",
              "aria-label": "Reset reasoning effort",
              disabled: effort.value === effort.default,
              onClick: () => choose("effort", effort.default),
            },
            h(Icon, { path: icons.reset }),
          ),
      ),
      h(
        "button",
        { type: "button", className: "popover-menu-item", popoverTarget: `${base}-models` },
        h("span", { className: "chat-composer-label" }, label(model)),
        h(Icon, { path: icons.right }),
      ),
      efforts.length > 1 &&
        h(EffortSlider, {
          key: `${model.value}-${effort.value}`,
          efforts,
          value: effortIndex,
          onCommit: (next) => next !== effort.value && choose("effort", next),
        }),
      efforts.length > 1 &&
        h(
          "div",
          { className: "chat-composer-menu-row" },
          h("span", null, capitalize(efforts[0])),
          h("span", null, capitalize(efforts[efforts.length - 1])),
        ),
    ),
    h(
      "div",
      {
        id: `${base}-models`,
        popover: "auto",
        className: "popover popover-menu chat-composer-menu chat-composer-menu-end",
        "aria-label": "Choose a model",
        style: { positionAnchor: `--${base}-config` },
      },
      h("div", { className: "chat-composer-group" }, "Model"),
      ...model.choices.map((choice) => option("model", choice, model.value, `${base}-models`)),
    ),
  )
}

// Drafts survive a remount of the same conversation (for example a reconnect).
const drafts = new Map()

function Composer(props) {
  const id = props.state.conversationId
  const metadata = props.metadata || {}
  const [value, setValue] = useState(() => drafts.get(id) || "")
  const [error, setError] = useState()
  const { submit, busy, notice } = useChatSubmission(props)

  function update(next) {
    drafts.set(id, next)
    setValue(next)
  }

  return h(
    "div",
    { className: "flex flex-col" },
    h(Context, { metadata }),
    h(
      Chat.Composer,
      {
        // The demo's look: borderless input, icon actions (one send/stop).
        compact: true,
        className: "chat-composer-ghost rounded-3xl",
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
          placeholder: props.active ? "Add to what Codex is doing" : "Do anything",
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
      },
      h(Settings, { metadata, bridge: props.bridge, conversationId: id }),
    ),
  )
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
