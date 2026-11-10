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
  folder:
    "M20,18H4V8H20M20,6H12L10,4H4C2.89,4 2,4.89 2,6V18A2,2 0 0,0 4,20H20A2,2 0 0,0 22,18V8C22,6.89 21.1,6 20,6Z",
  web:
    "M16.36,14C16.44,13.34 16.5,12.68 16.5,12C16.5,11.32 16.44,10.66 16.36,10H19.74C19.9,10.64 20,11.31 20,12C20,12.69 19.9,13.36 19.74,14M14.59,19.56C15.19,18.45 15.65,17.25 15.97,16H18.92C17.96,17.65 16.43,18.93 14.59,19.56M14.34,14H9.66C9.56,13.34 9.5,12.68 9.5,12C9.5,11.32 9.56,10.65 9.66,10H14.34C14.43,10.65 14.5,11.32 14.5,12C14.5,12.68 14.43,13.34 14.34,14M12,19.96C11.17,18.76 10.5,17.43 10.09,16H13.91C13.5,17.43 12.83,18.76 12,19.96M8,8H5.08C6.03,6.34 7.57,5.06 9.4,4.44C8.8,5.55 8.35,6.75 8,8M5.08,16H8C8.35,17.25 8.8,18.45 9.4,19.56C7.57,18.93 6.03,17.65 5.08,16M4.26,14C4.1,13.36 4,12.69 4,12C4,11.31 4.1,10.64 4.26,10H7.64C7.56,10.66 7.5,11.32 7.5,12C7.5,12.68 7.56,13.34 7.64,14M12,4.03C12.83,5.23 13.5,6.57 13.91,8H10.09C10.5,6.57 11.17,5.23 12,4.03M18.92,8H15.97C15.65,6.75 15.19,5.55 14.59,4.44C16.43,5.07 17.96,6.34 18.92,8M12,2C6.47,2 2,6.5 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2Z",
  laptop:
    "M4,6H20V16H4M20,18A2,2 0 0,0 22,16V6C22,4.89 21.1,4 20,4H4C2.89,4 2,4.89 2,6V16A2,2 0 0,0 4,18H0V20H24V18H20Z",
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

// Access, model and reasoning effort for the next message: a port of the
// duskmoon-react chat demo (packages/docs ChatSessionPreviews ChatComposerMenus),
// core chat-composer-menu classes and native popovers anchored to triggers.
// The server checks each choice (`chat.setting`) and pushes the new values in
// `metadata`; they apply to the next turn.
const ACCESS_HELP = {
  read_only: "Codex can read files but not change them.",
  default: "Edits in this project; asks before anything else.",
  full: "Runs any command without asking. Use with care.",
}

const capitalize = (text) => (text ? text[0].toUpperCase() + text.slice(1) : "")

// The demo's stroked icons.
function Stroke({ kind }) {
  const paths = {
    shield: "m12 3 8 4v5c0 5-8 9-8 9s-8-4-8-9V7ZM12 8v5M12 16h.01",
    down: "m6 9 6 6 6-6",
    right: "m9 6 6 6-6 6",
    check: "m5 12 4 4L19 6",
    reset: "M3 11a9 9 0 1 1 2.6 7.4M3 4v7h7",
  }
  return h(
    "svg",
    {
      width: 18,
      height: 18,
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      strokeWidth: 1.75,
      strokeLinecap: "round",
      strokeLinejoin: "round",
      "aria-hidden": true,
      focusable: false,
    },
    h("path", { d: paths[kind] }),
  )
}

// Moves locally while dragging; sends the effort once released.
function EffortSlider({ efforts, value, disabled, onCommit }) {
  const [index, setIndex] = useState(value)
  const commit = () => index !== value && onCommit(efforts[index])
  return h(
    "label",
    { className: "chat-composer-menu-field" },
    h("span", { className: "sr-only" }, "Reasoning effort"),
    h("input", {
      className: "range range-sm",
      type: "range",
      min: 0,
      max: efforts.length - 1,
      step: 1,
      value: index,
      disabled,
      "aria-valuetext": capitalize(efforts[index]),
      onChange: (event) => setIndex(Number(event.target.value)),
      onPointerUp: commit,
      onKeyUp: commit,
    }),
  )
}

function Settings({ metadata, bridge, conversationId }) {
  const [pending, setPending] = useState(false)
  const [feedback, setFeedback] = useState("")
  const settings = Object.fromEntries((metadata.settings || []).map((setting) => [setting.id, setting]))
  const { access, model, effort } = settings
  if (!access || !model || !effort) return null

  const base = `session-${conversationId}`.replace(/[^A-Za-z0-9_-]/g, "")
  const ids = { access: `${base}-access`, settings: `${base}-settings`, models: `${base}-models` }
  const anchors = { access: `--${base}-access`, settings: `--${base}-settings` }
  const label = (setting) => setting.choices.find((c) => c.value === setting.value)?.label || setting.value

  async function request(settingId, value) {
    if (pending || !value || value === settings[settingId].value) return
    setPending(true)
    setFeedback("")
    try {
      await bridge.send("setting", { settingId, value })
    } catch (error) {
      setFeedback(error.message)
    } finally {
      setPending(false)
    }
  }

  function choose(event, settingId, value) {
    request(settingId, value)
    event.currentTarget.closest("[popover]")?.hidePopover()
  }

  const efforts = effort.choices.map((c) => c.value)
  const effortIndex = Math.max(0, efforts.indexOf(effort.value))
  const full = access.value === "full"

  return h(
    React.Fragment,
    null,
    h(
      "button",
      {
        type: "button",
        className: `btn btn-ghost btn-sm chat-composer-config session-access${full ? " session-full-access" : ""}`,
        "aria-label": `Access: ${label(access)}`,
        title: `Access: ${label(access)}`,
        "data-session-access": true,
        popoverTarget: ids.access,
        style: { anchorName: anchors.access },
      },
      h(Stroke, { kind: "shield" }),
      h("span", { className: "chat-composer-label" }, label(access)),
    ),
    h(
      "div",
      {
        id: ids.access,
        popover: "auto",
        role: "group",
        "aria-label": "Access",
        className: "popover popover-menu chat-composer-menu",
        style: { positionAnchor: anchors.access },
      },
      h("div", { className: "chat-composer-group" }, "Access"),
      ...access.choices.map((choice) =>
        h(
          "button",
          {
            key: choice.value,
            type: "button",
            className: `popover-menu-item chat-composer-menu-option${choice.value === "full" ? " chat-composer-menu-option-warning" : ""}`,
            "aria-pressed": access.value === choice.value,
            disabled: pending,
            onClick: (event) => choose(event, "access", choice.value),
          },
          h(Stroke, { kind: "shield" }),
          h(
            "span",
            { className: "chat-composer-label" },
            choice.label,
            h("span", { className: "chat-composer-description" }, ACCESS_HELP[choice.value]),
          ),
          access.value === choice.value ? h(Stroke, { kind: "check" }) : null,
        ),
      ),
    ),
    metadata.pending &&
      h("span", { "data-session-pending": true, className: "chat-composer-description" }, "Applies to your next message"),
    h(
      "button",
      {
        type: "button",
        className: "btn btn-ghost btn-sm chat-composer-config session-model",
        "aria-label": `Model settings: ${label(model)}, ${capitalize(effort.value)}`,
        title: "Select model and reasoning effort",
        "data-session-model": true,
        popoverTarget: ids.settings,
        style: { anchorName: anchors.settings },
      },
      h(
        "span",
        { className: "chat-composer-label" },
        `${label(model)} `,
        h("span", { className: "session-effort" }, capitalize(effort.value)),
      ),
      h(Stroke, { kind: "down" }),
    ),
    h(
      "div",
      {
        id: ids.settings,
        popover: "auto",
        role: "group",
        "aria-label": "Composer model settings",
        tabIndex: -1,
        className: "popover popover-menu chat-composer-menu chat-composer-menu-end",
        style: { positionAnchor: anchors.settings },
      },
      h(
        "div",
        { className: "chat-composer-menu-row" },
        h("strong", null, capitalize(effort.value)),
        h(
          "button",
          {
            type: "button",
            className: "btn btn-ghost btn-xs btn-circle",
            "aria-label": "Reset reasoning effort",
            title: "Reset reasoning effort",
            disabled: pending || !effort.default || effort.value === effort.default,
            onClick: () => request("effort", effort.default),
          },
          h(Stroke, { kind: "reset" }),
        ),
      ),
      h(
        "button",
        {
          type: "button",
          className: "popover-menu-item",
          "aria-label": `Choose a model: ${label(model)}`,
          disabled: pending,
          popoverTarget: ids.models,
        },
        h("span", { className: "chat-composer-label" }, label(model)),
        h(Stroke, { kind: "right" }),
      ),
      efforts.length > 1 &&
        h(EffortSlider, {
          key: `${model.value}-${effort.value}`,
          efforts,
          value: effortIndex,
          disabled: pending,
          onCommit: (next) => request("effort", next),
        }),
      efforts.length > 1 &&
        h(
          "div",
          { className: "chat-composer-menu-row chat-composer-description" },
          h("span", null, capitalize(efforts[0])),
          h("span", null, capitalize(efforts[efforts.length - 1])),
        ),
      feedback ? h("p", { role: "status", className: "chat-composer-menu-field" }, feedback) : null,
      h(
        "div",
        {
          id: ids.models,
          popover: "auto",
          role: "group",
          "aria-label": "Choose a model",
          className: "popover popover-menu chat-composer-menu chat-composer-menu-end",
          style: { positionAnchor: anchors.settings },
        },
        h("div", { className: "chat-composer-group" }, "Select model"),
        ...model.choices.map((choice) =>
          h(
            "button",
            {
              key: choice.value,
              type: "button",
              className: "popover-menu-item chat-composer-menu-option",
              "aria-pressed": model.value === choice.value,
              disabled: pending,
              onClick: (event) => choose(event, "model", choice.value),
            },
            h("span", { className: "chat-composer-label" }, choice.label),
            model.value === choice.value ? h(Stroke, { kind: "check" }) : null,
          ),
        ),
      ),
    ),
    h("span", { className: "sr-only", role: "status" }, pending ? "Change pending" : feedback),
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
