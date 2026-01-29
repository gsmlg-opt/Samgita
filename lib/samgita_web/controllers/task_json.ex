defmodule SamgitaWeb.TaskJSON do
  alias Samgita.Domain.Task

  def index(%{tasks: tasks}) do
    %{data: for(task <- tasks, do: data(task))}
  end

  def show(%{task: task}) do
    %{data: data(task)}
  end

  defp data(%Task{} = task) do
    %{
      id: task.id,
      type: task.type,
      priority: task.priority,
      status: task.status,
      payload: task.payload,
      result: task.result,
      error: task.error,
      attempts: task.attempts,
      project_id: task.project_id,
      inserted_at: task.inserted_at,
      updated_at: task.updated_at
    }
  end
end
