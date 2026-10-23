defmodule SamgitaCodexDriver.ImageFixture do
  @moduledoc false

  import ExUnit.Assertions

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  def png(width, height) do
    row = <<0>> <> :binary.copy(<<17, 34, 51>>, width)
    pixels = :zlib.compress(:binary.copy(row, height))
    header = <<width::32, height::32, 8, 2, 0, 0, 0>>

    @signature <> chunk("IHDR", header) <> chunk("IDAT", pixels) <> chunk("IEND", <<>>)
  end

  def data_url(bytes), do: "data:image/png;base64," <> Base.encode64(bytes)

  def decode_png!("data:image/png;base64," <> encoded) do
    bytes = Base.decode64!(encoded)
    <<signature::binary-size(8), body::binary>> = bytes
    assert signature == @signature
    [{"IHDR", header} | rest] = chunks(body)
    <<width::32, height::32, 8, color, 0, 0, 0>> = header
    assert width in 1..6401 and height in 1..3201
    assert color in [2, 6]
    {data, ending} = Enum.split_while(rest, fn {kind, _} -> kind == "IDAT" end)
    assert data != []
    assert ending == [{"IEND", <<>>}]
    compressed = data |> Enum.map(&elem(&1, 1)) |> IO.iodata_to_binary()
    raw = :zlib.uncompress(compressed)
    pixel = if color == 2, do: <<17, 34, 51>>, else: <<17, 34, 51, 255>>
    row_bytes = width * byte_size(pixel)
    assert byte_size(raw) == height * (row_bytes + 1)

    verify_uniform_rows(raw, row_bytes, uniform_filters(pixel, width), true)
    {bytes, {width, height}}
  end

  # These fixtures permit only the chunks produced by their RGB/RGBA encoders.
  defp chunks(<<>>), do: []

  defp chunks(bytes) do
    assert byte_size(bytes) >= 12
    <<size::32, kind::binary-size(4), rest::binary>> = bytes
    assert kind in ["IHDR", "IDAT", "IEND"]
    assert byte_size(rest) >= size + 4
    <<data::binary-size(size), crc::32, tail::binary>> = rest
    assert crc == :erlang.crc32(kind <> data)
    [{kind, data} | chunks(tail)]
  end

  # A uniform image has known residuals for every PNG filter, so complete pixel
  # verification needs only row binaries rather than a list for every channel.
  defp uniform_filters(pixel, width) do
    full = :binary.copy(pixel, width)
    zeros = :binary.copy(<<0>>, byte_size(full))
    zero_tail = :binary.copy(<<0>>, byte_size(pixel) * (width - 1))
    sub = pixel <> zero_tail
    half = for <<channel <- pixel>>, into: <<>>, do: <<channel - div(channel, 2)>>

    {
      %{0 => full, 1 => sub, 2 => full, 3 => pixel <> :binary.copy(half, width - 1), 4 => sub},
      %{0 => full, 1 => sub, 2 => zeros, 3 => half <> zero_tail, 4 => zeros}
    }
  end

  defp verify_uniform_rows(<<>>, _row_bytes, _filters, _first), do: :ok

  defp verify_uniform_rows(bytes, row_bytes, {first, later} = filters, first?) do
    <<filter, row::binary-size(row_bytes), rest::binary>> = bytes
    assert filter in 0..4
    expected = if first?, do: first, else: later
    assert row == Map.fetch!(expected, filter)
    verify_uniform_rows(rest, row_bytes, filters, false)
  end

  defp chunk(kind, bytes) do
    <<byte_size(bytes)::32, kind::binary, bytes::binary, :erlang.crc32(kind <> bytes)::32>>
  end
end
