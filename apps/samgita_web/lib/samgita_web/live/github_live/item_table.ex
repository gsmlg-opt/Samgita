defmodule SamgitaWeb.GitHubLive.ItemTable do
  @moduledoc "Open GitHub item tables shared by repository and cross-repository views."
  use SamgitaWeb, :html
  alias SamgitaWeb.GitHubLive.ItemActions

  attr :id, :string, required: true
  attr :kind, :atom, values: [:issues, :pulls], required: true
  attr :rows, :list, required: true
  attr :jobs, :map, required: true
  attr :show_repository, :boolean, default: false
  attr :empty_message, :string, required: true
  attr :empty_id, :string, default: nil

  def table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table id={@id} class="table w-full">
        <thead>
          <tr>
            <th scope="col">#</th>
            <th :if={@show_repository} scope="col">{gettext("Repository")}</th>
            <th scope="col">{gettext("Title")}</th>
            <th scope="col">{gettext("Author")}</th>
            <th :if={@kind == :issues} scope="col">{gettext("Type")}</th>
            <th scope="col">{gettext("Labels")}</th>
            <th scope="col">{gettext("Updated")}</th>
            <th scope="col">{gettext("Actions")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@rows == []}>
            <td
              id={@empty_id}
              colspan={if(@kind == :issues, do: 7, else: 6) + if(@show_repository, do: 1, else: 0)}
              class="text-on-surface-variant"
            >
              {@empty_message}
            </td>
          </tr>
          <.row
            :for={item <- @rows}
            item={item}
            kind={@kind}
            jobs={@jobs}
            show_repository={@show_repository}
          />
        </tbody>
      </table>
    </div>
    """
  end

  defp row(assigns) do
    %{item: item, kind: kind} = assigns

    {prefix, key} =
      if assigns.show_repository,
        do: {"github-item", "#{item.repository_id}-#{item.number}"},
        else: {"github-repository-#{kind}-item", to_string(item.number)}

    assigns =
      assign(assigns,
        item_key: key,
        row_id: "#{prefix}-#{key}",
        pending: ItemActions.pending?(assigns.jobs, item.repository_id, kind, item.number)
      )

    ~H"""
    <tr id={@row_id}>
      <th scope="row" class="font-normal">#{@item.number}</th>
      <td :if={@show_repository} class="max-w-52">
        <.link
          navigate={~p"/github/repository/#{@item.repository_id}?#{[tab: @kind]}"}
          class="break-words text-primary hover:underline"
        >{@item.full_name}</.link>
      </td>
      <td class="min-w-48 max-w-md">
        <a
          href={@item.url}
          target="_blank"
          rel="noopener noreferrer"
          class="break-words font-semibold text-primary hover:underline"
        >{@item.title}</a>
      </td>
      <td>{@item.author}</td>
      <td :if={@kind == :issues}>{Map.get(@item, :issue_type) || "—"}</td>
      <td>
        <span class="flex max-w-56 flex-wrap gap-1">
          <.dm_badge
            :for={label <- Map.get(@item, :labels, []) || []}
            variant="neutral"
            style={label_style(Map.get(@item, :label_colors), label)}
          >
            {label}
          </.dm_badge>
        </span>
      </td>
      <td class="whitespace-nowrap text-sm text-on-surface-variant">
        <time datetime={@item.updated_at}>{readable_time(@item.updated_at)}</time>
      </td>
      <td>
        <div class="flex min-w-max flex-wrap items-center gap-2">
          <.dm_tooltip
            :let={trigger_attrs}
            id={"github-copy-help-#{@kind}-#{@item_key}"}
            class="tooltip-multiline"
            content={copy_description(@kind, @item)}
          >
            <button
              id={"github-copy-#{@kind}-#{@item_key}"}
              type="button"
              phx-hook="GitHubClipboard"
              data-copy-text={@item.url}
              data-feedback-id="github-copy-status"
              data-copy-success={gettext("Link copied.")}
              data-copy-error={
                gettext("Could not copy this link. Open it and copy the browser address.")
              }
              class="btn btn-ghost btn-square btn-sm"
              aria-label={copy_accessible_name(@kind, @item.number)}
              {trigger_attrs}
            >
              <.dm_mdi name="content-copy" class="size-4" aria-hidden="true" />
            </button>
          </.dm_tooltip>
          <.dm_tooltip
            :let={trigger_attrs}
            :for={
              action <- if(@kind == :issues, do: [:close_issue], else: [:close_pull, :approve_pull])
            }
            id={"github-action-help-#{action}-#{@item_key}"}
            class="tooltip-multiline"
            content={action_description(action, @item)}
          >
            <.dm_btn
              id={"github-action-#{action}-#{@item_key}"}
              type="button"
              variant="ghost"
              size="sm"
              shape="square"
              phx-click="repository_action"
              phx-value-action={action}
              phx-value-repository-id={@item.repository_id}
              phx-value-number={@item.number}
              phx-value-head-sha={
                if ItemActions.revision_action?(action), do: Map.get(@item, :head_sha)
              }
              disabled={
                @pending ||
                  (ItemActions.revision_action?(action) && is_nil(Map.get(@item, :head_sha)))
              }
              aria-label={ItemActions.accessible_name(action, @item.number)}
              {trigger_attrs}
              {close_confirmation(action, @item)}
            >
              <.dm_mdi name={action_icon(action)} class="size-4" aria-hidden="true" />
            </.dm_btn>
          </.dm_tooltip>
          <.merge_dialog
            :if={@kind == :pulls}
            item={@item}
            item_key={@item_key}
            disabled={@pending || is_nil(@item.head_sha)}
          />
        </div>
        <p
          :if={@kind == :pulls && is_nil(Map.get(@item, :head_sha))}
          class="mt-1 max-w-sm text-xs text-on-surface-variant"
        >
          {gettext("Sync to load the pull request head before approving or merging.")}
        </p>
      </td>
    </tr>
    """
  end

  defp merge_dialog(assigns) do
    item = assigns.item
    # A new head must dismiss the previous revision's confirmation.
    dialog_id = "github-merge-dialog-#{item.repository_id}-#{item.number}-#{item.head_sha}"
    assigns = assign(assigns, :dialog_id, dialog_id)

    ~H"""
    <.dm_modal
      id={@dialog_id}
      hide_close
      size="sm"
      phx-hook="GitHubMergeDialog"
      aria-describedby={@dialog_id <> "-target"}
    >
      <:trigger :let={id}>
        <.dm_tooltip
          :let={trigger_attrs}
          id={"github-action-help-merge_pull-#{@item_key}"}
          class="tooltip-multiline"
          content={
            gettext("Choose a merge method for pull request #%{number} in %{repository}.",
              number: @item.number,
              repository: @item.full_name
            )
          }
        >
          <.dm_btn
            id={"github-action-merge_pull-#{@item_key}"}
            variant="ghost"
            size="sm"
            shape="square"
            command="show-modal"
            commandfor={id}
            disabled={@disabled}
            aria-haspopup="dialog"
            aria-controls={id}
            aria-label={ItemActions.accessible_name(:merge_pull, @item.number)}
            {trigger_attrs}
          >
            <.dm_mdi name="source-merge" class="size-4" aria-hidden="true" />
          </.dm_btn>
        </.dm_tooltip>
      </:trigger>
      <:title>{ItemActions.accessible_name(:merge_pull, @item.number)}</:title>
      <:body>
        <p id={@dialog_id <> "-target"} class="break-words">
          <span class="font-semibold">{@item.full_name}</span> · {@item.title}
        </p>
        <form id={@dialog_id <> "-form"} method="dialog" phx-submit="repository_action" class="mt-4">
          <input type="hidden" name="repository-id" value={@item.repository_id} />
          <input type="hidden" name="number" value={@item.number} />
          <input type="hidden" name="head-sha" value={@item.head_sha} />
          <fieldset class="space-y-2" disabled={@disabled}>
            <legend class="font-semibold">{gettext("Merge method")}</legend>
            <label
              :for={
                {method, name} <- [
                  {:merge_pull, gettext("Create a merge commit")},
                  {:rebase_pull, gettext("Rebase and merge")}
                ]
              }
              class="flex items-center gap-2"
            >
              <input type="radio" name="action" value={method} required class="radio radio-primary" />
              {name}
            </label>
          </fieldset>
        </form>
      </:body>
      <:footer>
        <.dm_btn variant="ghost" command="close" commandfor={@dialog_id} autofocus>
          {gettext("Cancel")}
        </.dm_btn>
        <.dm_btn native_submit form={@dialog_id <> "-form"} variant="primary" disabled={@disabled}>
          {gettext("Confirm merge")}
        </.dm_btn>
      </:footer>
    </.dm_modal>
    """
  end

  attr :status, :string, default: nil
  attr :error, :string, default: nil

  def feedback(assigns) do
    ~H"""
    <p
      :if={@status}
      id="github-action-status"
      role="status"
      class="text-sm text-on-surface-variant"
    >
      {@status}
    </p>
    <p :if={@error} id="github-action-error" role="alert" class="text-error">
      {@error}
    </p>
    <p
      id="github-copy-status"
      phx-update="ignore"
      role="status"
      aria-live="polite"
      class="text-sm text-on-surface-variant"
    >
    </p>
    """
  end

  attr :issue, :map, required: true
  attr :jobs, :map, required: true
  attr :repository_name, :string, default: nil

  def closed_issue(assigns) do
    ~H"""
    <div id="github-closed-issue" class="flex flex-wrap items-center gap-3">
      <span :if={@repository_name} class="font-semibold">{@repository_name}</span>
      <span>{gettext("Issue #%{number} is closed.", number: @issue.number)}</span>
      <button
        id="github-reopen-closed-issue"
        type="button"
        phx-click="reopen_closed_issue"
        disabled={ItemActions.pending?(@jobs, @issue.repository_id, :issues, @issue.number)}
        class="btn btn-ghost btn-sm"
      >
        {gettext("Reopen #%{number}", number: @issue.number)}
      </button>
    </div>
    """
  end

  def readable_time(nil), do: "—"
  def readable_time(%DateTime{} = date), do: Calendar.strftime(date, "%Y-%m-%d %H:%M UTC")

  def readable_time(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _} -> readable_time(date)
      _ -> value
    end
  end

  defp copy_accessible_name(:issues, number),
    do: gettext("Copy link to issue #%{number}", number: number)

  defp copy_accessible_name(:pulls, number),
    do: gettext("Copy link to pull request #%{number}", number: number)

  defp close_confirmation(action, item) when action in [:close_issue, :close_pull] do
    %{
      confirm_title: ItemActions.accessible_name(action, item.number),
      confirm:
        gettext("Close “%{title}” in %{repository} on GitHub?",
          title: item.title,
          repository: item.full_name
        ),
      confirm_text:
        if(action == :close_issue,
          do: gettext("Close issue"),
          else: gettext("Close pull request")
        ),
      cancel_text: gettext("Cancel")
    }
  end

  defp close_confirmation(_action, _item), do: %{}

  defp action_icon(action) when action in [:close_issue, :close_pull], do: "close-circle-outline"
  defp action_icon(:approve_pull), do: "check-circle-outline"

  defp action_description(:close_issue, item),
    do:
      gettext("Close issue #%{number} in %{repository}.",
        number: item.number,
        repository: item.full_name
      )

  defp action_description(:close_pull, item),
    do:
      gettext("Close pull request #%{number} in %{repository}.",
        number: item.number,
        repository: item.full_name
      )

  defp action_description(:approve_pull, item),
    do:
      gettext("Approve pull request #%{number} in %{repository} at the displayed commit.",
        number: item.number,
        repository: item.full_name
      )

  defp copy_description(:issues, item),
    do:
      gettext("Copy the link to issue #%{number} in %{repository}.",
        number: item.number,
        repository: item.full_name
      )

  defp copy_description(:pulls, item),
    do:
      gettext("Copy the link to pull request #%{number} in %{repository}.",
        number: item.number,
        repository: item.full_name
      )

  defp label_style(colors, label) when is_map(colors) do
    with color when is_binary(color) and byte_size(color) == 6 <- Map.get(colors, label),
         {:ok, <<red, green, blue>>} <- Base.decode16(color, case: :lower) do
      luminance =
        0.2126 * linear_channel(red) + 0.7152 * linear_channel(green) +
          0.0722 * linear_channel(blue)

      black_contrast = (luminance + 0.05) / 0.05
      white_contrast = 1.05 / (luminance + 0.05)
      foreground = if black_contrast >= white_contrast, do: "#000000", else: "#ffffff"
      "background-color: ##{color}; color: #{foreground}; border-color: ##{color}"
    else
      _ -> nil
    end
  end

  defp label_style(_colors, _label), do: nil

  defp linear_channel(channel) do
    value = channel / 255
    if value <= 0.04045, do: value / 12.92, else: :math.pow((value + 0.055) / 1.055, 2.4)
  end
end
