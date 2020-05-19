defmodule Result do
  def ok(value) do
    {:ok, value}
  end

  def err(value) do
    {:err, value}
  end

  def map(input, f) do
    case input do
      {:ok, value} -> f.(value)
      _ -> input
    end
  end

  def map_raw(input, f) do
    case input do
      {:ok, value} -> ok(f.(value))
      _ -> input
    end
  end

  def map_err(input, f) do
    case input do
      {:err, value} -> f.(value)
      _ -> input
    end
  end

  def to_value({_, value}) do
    value
  end

  def to_result(value) do
    case value do
      :ok -> {:ok, {}}
      {:ok, val} -> {:ok, val}
      :err -> {:err, {}}
      {:err, val} -> {:err, val}
      _ -> value
    end
  end
end
