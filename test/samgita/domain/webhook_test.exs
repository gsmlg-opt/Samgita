defmodule Samgita.Domain.WebhookTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.Webhook

  describe "changeset/2" do
    test "valid with required fields" do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          url: "https://example.com/hook",
          events: ["task.completed"]
        })

      assert changeset.valid?
    end

    test "invalid without url" do
      changeset =
        Webhook.changeset(%Webhook{}, %{events: ["task.completed"]})

      refute changeset.valid?
      assert %{url: ["can't be blank"]} = errors_on(changeset)
    end

    test "valid without events uses default empty list" do
      changeset =
        Webhook.changeset(%Webhook{}, %{url: "https://example.com/hook"})

      # events defaults to [] in schema, so validate_required sees it as present
      assert changeset.valid?
    end

    test "rejects invalid URL scheme" do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          url: "ftp://example.com/hook",
          events: ["task.completed"]
        })

      refute changeset.valid?
      assert %{url: ["must be a valid HTTP/HTTPS URL"]} = errors_on(changeset)
    end

    test "accepts http URL" do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          url: "http://localhost:4000/hook",
          events: ["task.completed"]
        })

      assert changeset.valid?
    end

    test "rejects invalid events" do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          url: "https://example.com/hook",
          events: ["invalid.event"]
        })

      refute changeset.valid?
      assert %{events: [msg]} = errors_on(changeset)
      assert msg =~ "invalid events"
    end

    test "accepts all valid events" do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          url: "https://example.com/hook",
          events: Webhook.valid_events()
        })

      assert changeset.valid?
    end

    test "defaults active to true" do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          url: "https://example.com/hook",
          events: ["task.completed"]
        })

      webhook = Ecto.Changeset.apply_changes(changeset)
      assert webhook.active == true
    end

    test "accepts optional fields" do
      changeset =
        Webhook.changeset(%Webhook{}, %{
          url: "https://example.com/hook",
          events: ["task.completed", "task.failed"],
          secret: "my-secret-key",
          active: false
        })

      assert changeset.valid?
    end

    test "valid_events/0 returns all event types" do
      events = Webhook.valid_events()
      assert length(events) == 6
      assert "project.phase_changed" in events
      assert "task.completed" in events
      assert "task.failed" in events
      assert "agent.spawned" in events
      assert "agent.crashed" in events
      assert "project.completed" in events
    end
  end
end
