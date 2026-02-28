defmodule SamgitaProvider.Provider do
  @moduledoc "Behaviour for LLM CLI provider implementations."

  @callback query(prompt :: String.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, atom() | String.t()}
end
