defmodule Samgita.FeaturesTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.Feature
  alias Samgita.Features

  @valid_attrs %{
    name: "Test Feature",
    description: "A test feature with enough description length"
  }

  defp unique_name, do: "Feature #{System.unique_integer([:positive])}"

  defp create_feature(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{name: unique_name(), description: "A feature description for testing"},
        attrs
      )

    {:ok, feature} = Features.create_feature(attrs)
    feature
  end

  describe "list_features/1" do
    test "returns empty list when no features" do
      assert Features.list_features() == []
    end

    test "returns all features" do
      feature = create_feature()
      features = Features.list_features()
      assert length(features) == 1
      assert hd(features).id == feature.id
    end

    test "filters by status" do
      _draft = create_feature(%{status: :draft})
      active = create_feature(%{status: :active, enabled: true})

      results = Features.list_features(%{"status" => "active"})
      assert length(results) == 1
      assert hd(results).id == active.id
    end

    test "filters by enabled" do
      _disabled = create_feature()
      enabled = create_feature(%{enabled: true})

      results = Features.list_features(%{"enabled" => "true"})
      assert length(results) == 1
      assert hd(results).id == enabled.id
    end

    test "filters by priority" do
      _medium = create_feature()
      high = create_feature(%{priority: :high})

      results = Features.list_features(%{"priority" => "high"})
      assert length(results) == 1
      assert hd(results).id == high.id
    end

    test "ignores unknown filters" do
      create_feature()
      results = Features.list_features(%{"unknown" => "value"})
      assert length(results) == 1
    end
  end

  describe "get_feature/1" do
    test "returns feature when found" do
      feature = create_feature()
      assert {:ok, found} = Features.get_feature(feature.id)
      assert found.id == feature.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Features.get_feature(Ecto.UUID.generate())
    end
  end

  describe "get_feature_by_name/1" do
    test "returns feature when found" do
      feature = create_feature(%{name: "Unique Name"})
      assert {:ok, found} = Features.get_feature_by_name("Unique Name")
      assert found.id == feature.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Features.get_feature_by_name("Nonexistent")
    end
  end

  describe "create_feature/1" do
    test "creates feature with valid attrs" do
      assert {:ok, %Feature{} = feature} = Features.create_feature(@valid_attrs)
      assert feature.name == "Test Feature"
      assert feature.status == :draft
      assert feature.priority == :medium
      assert feature.enabled == false
    end

    test "returns error for missing required fields" do
      assert {:error, changeset} = Features.create_feature(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error for too short name" do
      assert {:error, changeset} =
               Features.create_feature(%{name: "AB", description: "Valid description here"})

      assert %{name: _} = errors_on(changeset)
    end

    test "enforces unique name" do
      create_feature(%{name: "Duplicate Name"})

      assert {:error, changeset} =
               Features.create_feature(%{
                 name: "Duplicate Name",
                 description: "Another feature with same name"
               })

      assert %{name: _} = errors_on(changeset)
    end
  end

  describe "update_feature/2" do
    test "updates with valid attrs" do
      feature = create_feature()

      assert {:ok, updated} =
               Features.update_feature(feature, %{
                 description: "Updated description with enough length"
               })

      assert updated.description == "Updated description with enough length"
    end

    test "returns error for invalid attrs" do
      feature = create_feature()
      assert {:error, _changeset} = Features.update_feature(feature, %{name: "AB"})
    end
  end

  describe "delete_feature/1" do
    test "deletes the feature" do
      feature = create_feature()
      assert {:ok, _} = Features.delete_feature(feature)
      assert {:error, :not_found} = Features.get_feature(feature.id)
    end
  end

  describe "enable_feature/1" do
    test "enables a feature" do
      feature = create_feature()
      assert {:ok, enabled} = Features.enable_feature(feature)
      assert enabled.enabled == true
    end
  end

  describe "disable_feature/1" do
    test "disables a feature" do
      feature = create_feature(%{enabled: true})
      assert {:ok, disabled} = Features.disable_feature(feature)
      assert disabled.enabled == false
    end
  end

  describe "archive_feature/1" do
    test "archives a feature" do
      feature = create_feature()
      assert {:ok, archived} = Features.archive_feature(feature)
      assert archived.status == :archived
      assert archived.enabled == false
    end
  end

  describe "change_feature/2" do
    test "returns a changeset" do
      feature = create_feature()
      changeset = Features.change_feature(feature)
      assert %Ecto.Changeset{} = changeset
    end
  end
end
