defmodule Axon.Adapters.Security.RemoteAddress do
  @moduledoc false

  @type ip :: :inet.ip_address()

  @spec allowed?(ip(), keyword()) :: boolean()
  def allowed?(ip, opts \\ []) do
    allow_loopback? = Keyword.get(opts, :allow_loopback, true)
    allow_private? = Keyword.get(opts, :allow_private, true)

    cond do
      allow_loopback? and loopback?(ip) ->
        true

      allow_private? and private?(ip) ->
        true

      true ->
        false
    end
  end

  @spec loopback?(ip()) :: boolean()
  def loopback?({127, _b, _c, _d}), do: true
  def loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  def loopback?(_), do: false

  @spec private?(ip()) :: boolean()
  def private?({10, _b, _c, _d}), do: true
  def private?({172, b, _c, _d}) when b in 16..31, do: true
  def private?({192, 168, _c, _d}), do: true
  def private?({a, _b, _c, _d, _e, _f, _g, _h}) when a in 0xFC00..0xFDFF, do: true
  def private?(_), do: false
end
