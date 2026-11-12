// Codex session chat: the DuskMoon React chat with the public composition API
// (phoenix_duskmoon guides/react-chat.md). The default hook composer is a
// single-line input; Chat.Composer is the multi-line composer of the DuskMoon
// chat demo (Enter sends, Shift+Enter inserts a newline, Stop while working).
import React, { useEffect, useState } from "react"
import { Chat, ComposerSettings } from "@duskmoon-dev/components/chat"
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
// the host with its connection status; it is attached above the composer.
function Context({ metadata, bridge }) {
  const { project, location, host, connected, goal, plan } = metadata
  return h(
    Chat.ComposerContext,
    { "data-session-context": true },
    project && h(Chat.ComposerContextItem, { icon: h(Icon, { path: icons.folder }) }, project),
    h(Chat.ComposerContextItem, { icon: h(Icon, { path: location === "Local" ? icons.laptop : icons.web }) }, location),
    plan &&
      h(
        Chat.ComposerContextItem,
        { icon: h(Stroke, { kind: "bulb" }), className: "text-primary", "data-session-plan": true },
        "Plan mode",
      ),
    goal &&
      h(
        Chat.ComposerContextItem,
        {
          icon: h(Stroke, { kind: "target" }),
          title: goal.objective,
          "data-session-goal": true,
          action: {
            label: "Clear goal",
            onClick: () => bridge.send("goal_clear", {}).catch(() => {}),
            children: h(Stroke, { kind: "x" }),
          },
        },
        goal.objective,
      ),
    host &&
      h(
        Chat.ComposerContextEnd,
        null,
        h(Chat.ComposerContextItem, null, host),
        h(Chat.ComposerConnection, {
          state: connected ? "connected" : "disconnected",
          label: connected ? "Connected" : "Not connected",
        }),
      ),
  )
}

// Stroked icons for the composer's menus and context.
function Stroke({ kind }) {
  const paths = {
    shield: "m12 3 8 4v5c0 5-8 9-8 9s-8-4-8-9V7ZM12 8v5M12 16h.01",
    plus: "M12 5v14M5 12h14",
    paperclip: "m21 12-8.5 8.5a5 5 0 0 1-7-7l9-9a3.5 3.5 0 0 1 5 5l-9 9a2 2 0 0 1-3-3l8.5-8.5",
    target: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10ZM12 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z",
    bulb: "M9 18h6M10 22h4M12 2a7 7 0 0 0-4 12.7V17h8v-2.3A7 7 0 0 0 12 2Z",
    plug: "M9 2v6M15 2v6M6 8h12v4a6 6 0 0 1-12 0ZM12 18v4",
    book: "M4 19.5A2.5 2.5 0 0 1 6.5 17H20V3H6.5A2.5 2.5 0 0 0 4 5.5ZM4 19.5V21h16",
    folder: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z",
    file: "M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9ZM14 3v6h6",
    up: "m18 15-6-6-6 6",
    x: "M18 6 6 18M6 6l12 12",
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

// Access, model and reasoning effort for the next message, as DuskMoon's
// composer settings menus. The server checks each choice (`chat.setting`),
// counts the change in `settings_revision` and pushes the new values in
// `metadata`; they apply to the next turn.
const SETTING_GROUPS = [
  { id: "access", label: "Access", settingIds: ["access"], appearance: "access", icon: h(Stroke, { kind: "shield" }) },
  { id: "model", label: "Model settings", settingIds: ["model", "effort"], nestedSettingIds: ["model"], appearance: "model" },
]

function Settings({ metadata, bridge, conversationId }) {
  const settings = (metadata.settings || []).filter((setting) => setting.id !== "mode")
  if (settings.length === 0) return null

  // A rejection keeps the shown value; transport failures surface as errors.
  async function onRequest(request) {
    const { requestId, scopeKey, settingId, value } = request
    try {
      const reply = await bridge.send("setting", { settingId, value })
      return { requestId, scopeKey, settingId, revision: reply.revision, outcome: "accepted", value: reply.value }
    } catch (error) {
      if (!error.response) throw error
      return { requestId, scopeKey, settingId, revision: request.expectedRevision, outcome: "rejected", message: error.message }
    }
  }

  return h(
    React.Fragment,
    null,
    h(ComposerSettings, {
      variant: "menu",
      groups: SETTING_GROUPS,
      scopeKey: conversationId,
      revision: metadata.settings_revision || 0,
      settings,
      onRequest,
      // The server pushes the acknowledged values in `metadata`.
      onAcknowledged: () => {},
    }),
    metadata.pending &&
      h("span", { "data-session-pending": true, className: "chat-composer-description" }, "Applies to your next message"),
  )
}

// The "+" Add menu of the Codex app: files and folders (inserted as paths, as
// the Codex TUI does), a session goal, plan mode, and plugins that are attached
// to the next message. Plugins come from the server (`chat.catalog`), which
// only accepts attachments from that list.
function AddMenu({ metadata, bridge, conversationId, onInsertPath, onAttach }) {
  const [catalog, setCatalog] = useState({ plugins: [] })
  const [notice, setNotice] = useState("")
  const base = `session-${conversationId}`.replace(/[^A-Za-z0-9_-]/g, "")
  const ids = { add: `${base}-add`, files: `${base}-files`, goal: `${base}-goal` }
  const anchor = `--${base}-add`

  async function refresh() {
    try {
      const reply = await bridge.send("catalog", {})
      setCatalog({ plugins: reply.plugins || [] })
    } catch (error) {
      setNotice(error.message)
    }
  }

  async function togglePlan(event) {
    event.currentTarget.closest("[popover]")?.hidePopover()
    try {
      await bridge.send("setting", { settingId: "mode", value: metadata.plan ? "default" : "plan" })
    } catch (error) {
      setNotice(error.message)
    }
  }

  const item = (key, icon, label, description, props) =>
    h(
      "button",
      { key, type: "button", className: "popover-menu-item", ...props },
      h("span", { className: "popover-menu-item-icon" }, h(Stroke, { kind: icon })),
      h(
        "span",
        { className: "chat-composer-label" },
        label,
        description && h("span", { className: "chat-composer-description" }, description),
      ),
    )

  const attach = (event, attachment) => {
    event.currentTarget.closest("[popover]")?.hidePopover()
    onAttach(attachment)
  }

  return h(
    React.Fragment,
    null,
    h(
      "button",
      {
        type: "button",
        className: "btn btn-ghost btn-sm btn-circle",
        "aria-label": "Add files and more",
        title: "Add files and more",
        "data-session-add": true,
        popoverTarget: ids.add,
        style: { anchorName: anchor },
      },
      h(Stroke, { kind: "plus" }),
    ),
    h(
      "div",
      {
        id: ids.add,
        popover: "auto",
        role: "group",
        "aria-label": "Add files and more",
        className: "popover popover-menu chat-composer-menu session-add-menu",
        style: { positionAnchor: anchor },
        onToggle: (event) => event.newState === "open" && refresh(),
      },
      h("div", { className: "chat-composer-group" }, "Add"),
      item("files", "paperclip", "Files and folders", null, { popoverTarget: ids.files }),
      item("goal", "target", "Goal", metadata.goal ? "Change the goal" : "Set a goal to keep pursuing", {
        popoverTarget: ids.goal,
      }),
      item("plan", "bulb", "Plan mode", metadata.plan ? "Turn plan mode off" : "Turn plan mode on", {
        "aria-pressed": !!metadata.plan,
        onClick: togglePlan,
      }),
      catalog.plugins.length > 0 && h("div", { className: "chat-composer-group" }, "Plugins"),
      ...catalog.plugins.map((plugin) =>
        item(plugin.path, "plug", plugin.name, plugin.description, {
          onClick: (event) => attach(event, { type: "mention", name: plugin.name, path: plugin.path }),
        }),
      ),
      notice && h("p", { role: "status", className: "chat-composer-menu-field text-error" }, notice),
    ),
    h(FilesPanel, { id: ids.files, anchor, bridge, onInsertPath }),
    h(GoalPanel, { id: ids.goal, anchor, bridge, goal: metadata.goal }),
  )
}

// Browse the Codex machine from the project folder; a file, or a folder's
// "Add", inserts its path into the message.
function FilesPanel({ id, anchor, bridge, onInsertPath }) {
  const [listing, setListing] = useState(null)
  const [notice, setNotice] = useState("")

  async function open(path) {
    setNotice("")
    try {
      setListing(await bridge.send("files", path ? { path } : {}))
    } catch (error) {
      setNotice(error.message)
    }
  }

  function insert(event, path) {
    event.currentTarget.closest("[popover]")?.hidePopover()
    onInsertPath(path)
  }

  return h(
    "div",
    {
      id,
      popover: "auto",
      role: "group",
      "aria-label": "Files and folders",
      className: "popover popover-menu chat-composer-menu session-files",
      style: { positionAnchor: anchor },
      onToggle: (event) => event.newState === "open" && open(listing?.path),
    },
    h(
      "div",
      { className: "chat-composer-menu-row" },
      h("span", { className: "chat-composer-description truncate", title: listing?.path }, listing?.path || "Loading…"),
      listing?.parent &&
        h(
          "button",
          {
            type: "button",
            className: "btn btn-ghost btn-xs btn-circle",
            "aria-label": "Parent folder",
            title: "Parent folder",
            onClick: () => open(listing.parent),
          },
          h(Stroke, { kind: "up" }),
        ),
    ),
    ...(listing?.entries || []).map((entry) =>
      h(
        "div",
        { key: entry.path, className: "session-file-row" },
        h(
          "button",
          {
            type: "button",
            className: "popover-menu-item",
            title: entry.path,
            onClick: (event) => (entry.dir ? open(entry.path) : insert(event, entry.path)),
          },
          h("span", { className: "popover-menu-item-icon" }, h(Stroke, { kind: entry.dir ? "folder" : "file" })),
          h("span", { className: "chat-composer-label truncate" }, entry.name),
        ),
        entry.dir &&
          h(
            "button",
            {
              type: "button",
              className: "btn btn-ghost btn-xs",
              "aria-label": `Add ${entry.name}`,
              onClick: (event) => insert(event, entry.path),
            },
            "Add",
          ),
      ),
    ),
    listing && listing.entries.length === 0 && h("p", { className: "chat-composer-description chat-composer-menu-field" }, "Empty folder"),
    notice && h("p", { role: "status", className: "chat-composer-menu-field text-error" }, notice),
  )
}

// The goal Codex keeps pursuing in this session.
function GoalPanel({ id, anchor, bridge, goal }) {
  const [objective, setObjective] = useState(goal?.objective || "")
  const [notice, setNotice] = useState("")

  async function save(event) {
    event.preventDefault()
    const form = event.currentTarget
    setNotice("")
    try {
      await bridge.send("goal", { objective })
      form.closest("[popover]")?.hidePopover()
    } catch (error) {
      setNotice(error.message)
    }
  }

  return h(
    "div",
    {
      id,
      popover: "auto",
      role: "group",
      "aria-label": "Goal",
      className: "popover popover-menu chat-composer-menu session-goal",
      style: { positionAnchor: anchor },
      onToggle: (event) => event.newState === "open" && setObjective(goal?.objective || ""),
    },
    h("div", { className: "chat-composer-group" }, "Goal"),
    h(
      "form",
      { className: "chat-composer-menu-field flex flex-col gap-2", onSubmit: save },
      h("textarea", {
        className: "textarea textarea-sm w-full",
        rows: 3,
        value: objective,
        "aria-label": "Goal for Codex",
        placeholder: "What should Codex keep working towards?",
        onChange: (event) => setObjective(event.target.value),
      }),
      h(
        "div",
        { className: "flex justify-end gap-2" },
        h("button", { type: "submit", className: "btn btn-primary btn-sm", disabled: !objective.trim() }, "Set goal"),
      ),
    ),
    notice && h("p", { role: "status", className: "chat-composer-menu-field text-error" }, notice),
  )
}

// Plugins and skills attached to the next message.
function Attachments({ items, onRemove }) {
  if (items.length === 0) return null
  return h(
    "div",
    { className: "mx-4 flex flex-wrap gap-2 px-1 py-2", "data-session-attachments": true },
    ...items.map((item) =>
      h(
        "span",
        { key: item.path, className: "badge badge-outline gap-1" },
        h(Stroke, { kind: item.type === "skill" ? "book" : "plug" }),
        item.name,
        h(
          "button",
          {
            type: "button",
            className: "btn btn-ghost btn-xs btn-circle",
            "aria-label": `Remove ${item.name}`,
            onClick: () => onRemove(item),
          },
          h(Stroke, { kind: "x" }),
        ),
      ),
    ),
  )
}

// Drafts survive a remount of the same conversation (for example a reconnect).
const drafts = new Map()

function Composer(props) {
  const id = props.state.conversationId
  const metadata = props.metadata || {}
  const [value, setValue] = useState(() => drafts.get(id) || "")
  const [attachments, setAttachments] = useState([])
  const [skills, setSkills] = useState(null)
  const [error, setError] = useState()
  const { submit, busy, notice } = useChatSubmission(props)

  function update(next) {
    drafts.set(id, next)
    setValue(next)
  }

  // As in the Codex TUI: a path with whitespace is quoted.
  function insertPath(path) {
    const text = /\s/.test(path) && !path.includes('"') ? `"${path}"` : path
    update(value && !/\s$/.test(value) ? `${value} ${text} ` : `${value}${text} `)
  }

  const attach = (item) =>
    setAttachments((current) => (current.some((a) => a.path === item.path) ? current : [...current, item]))

  // Skills are triggered as in Codex: `$` or `/` starts a word that names a
  // skill. They are loaded from the server once, on the first trigger.
  const trigger = /(^|\s)([/$])([^\s/$]*)$/.exec(value)
  const triggered = trigger !== null
  useEffect(() => {
    if (!triggered || skills !== null) return
    setSkills([])
    props.bridge
      .send("catalog", {})
      .then((reply) => setSkills(reply.skills || []))
      .catch(() => setSkills([]))
  }, [triggered, skills])
  const query = trigger ? trigger[3].toLowerCase() : null
  const completion = {
    label: "Skills",
    items:
      query === null
        ? []
        : (skills || [])
            .filter((skill) => skill.name.toLowerCase().includes(query))
            .slice(0, 8)
            .map((skill) => ({
              id: skill.path,
              label: skill.name,
              description: skill.description,
              group: "Skills",
            })),
    onSelect: (item, context) => {
      const skill = (skills || []).find((s) => s.path === item.id)
      if (!skill) return
      // Remove the typed `$name` / `/name` before the caret.
      const before = context.value.slice(0, context.selectionStart).replace(/[/$][^\s/$]*$/, "")
      update(before + context.value.slice(context.selectionEnd))
      attach({ type: "skill", name: skill.name, path: skill.path })
    },
  }

  return h(
    "div",
    { className: "flex flex-col" },
    h(Attachments, { items: attachments, onRemove: (item) => setAttachments((c) => c.filter((a) => a !== item)) }),
    h(
      Chat.Composer,
      {
        // The demo's look: borderless input, icon actions (one send/stop).
        compact: true,
        className: "chat-composer-ghost rounded-3xl",
        context: h(Context, { metadata, bridge: props.bridge }),
        value,
        onValueChange: update,
        completion,
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
            await submit({ text: value, attachments: attachments.map(({ type, path }) => ({ type, path })) })
            drafts.delete(id)
            setAttachments([])
            return true
          } catch {
            // useChatSubmission keeps the rejection in `notice`; the draft stays.
            return false
          }
        },
      },
      h(AddMenu, { metadata, bridge: props.bridge, conversationId: id, onInsertPath: insertPath, onAttach: attach }),
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

// Codex asks before running a command or changing files. The decision is the
// server's (`chat.decide`); the request stays until Codex closes it.
const DECISIONS = [
  { id: "accept", label: "Approve", tone: "primary" },
  { id: "acceptForSession", label: "Approve for this session" },
  { id: "decline", label: "Decline", tone: "danger" },
]

function Request({ request, bridge }) {
  const [pending, setPending] = useState(false)
  const [notice, setNotice] = useState("")

  async function decide(decision) {
    setPending(true)
    setNotice("")
    try {
      await bridge.send("decide", { key: request.key, decision })
    } catch (error) {
      setNotice(error.message)
      setPending(false)
    }
  }

  return h(
    Chat.Request,
    {
      id: `request-${request.key}`,
      title: request.title,
      state: request.answerable ? "pending" : "answer-elsewhere",
      pending,
      actions: request.answerable
        ? DECISIONS.map((decision) => ({ ...decision, onSelect: () => decide(decision.id) }))
        : [],
      explanation: request.answerable
        ? notice && h("p", { role: "alert", className: "text-error" }, notice)
        : h("p", null, "Answer this request in a Codex app; Samgita cannot answer it yet."),
    },
    request.command && h("code", { className: "block whitespace-pre-wrap break-all" }, request.command),
    request.reason && h("p", null, request.reason),
    !request.answerable && h("p", null, request.method),
  )
}

function Message({ message, targetId, timeline, bridge }) {
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
    ...(message.requests || []).map((request) => h(Request, { key: request.key, request, bridge })),
    message.content
      ? h(Chat.Content, { streaming }, h(Markdown, { markdown: message.content }))
      : streaming && h(Chat.Typing, { "aria-label": "Codex is working" }),
  )
}

export const SessionChat = createDuskmoonReactChat({ Composer, renderMessage: Message })
