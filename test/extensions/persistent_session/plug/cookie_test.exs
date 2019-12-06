defmodule PowPersistentSession.Plug.CookieTest do
  use ExUnit.Case
  doctest PowPersistentSession.Plug.Cookie

  alias Plug.Conn
  alias Pow.{Plug, Plug.Session}
  alias Pow.Test.ConnHelpers
  alias PowPersistentSession.{Plug.Cookie, Store.PersistentSessionCache}
  alias PowPersistentSession.Test.Users.User

  @max_age Integer.floor_div(:timer.hours(24) * 30, 1000)

  setup do
    config = PowPersistentSession.Test.pow_config()
    ets    = Pow.Config.get(config, :cache_store_backend, nil)

    ets.init()

    conn =
      :get
      |> ConnHelpers.conn("/")
      |> ConnHelpers.init_session()
      |> Session.call(config)

    {:ok, %{conn: conn, config: config, ets: ets}}
  end

  defp store_persistent(conn, ets, id, value, cookie_key \\ "persistent_session_cookie") do
    PersistentSessionCache.put([backend: ets], id, value)
    persistent_cookie(conn, cookie_key, id)
  end

  defp persistent_cookie(conn, cookie_key, id) do
    cookies = Map.new([{cookie_key, id}])
    %{conn | req_cookies: cookies, cookies: cookies}
  end

  test "call/2 sets pow_persistent_session plug in conn", %{conn: conn, config: config} do
    conn            = Cookie.call(conn, Cookie.init([]))
    expected_config = [mod: Session, plug: Session] ++ config

    assert {Cookie, ^expected_config} = conn.private[:pow_persistent_session]
    refute conn.resp_cookies["persistent_session_cookie"]
  end

  test "call/2 assigns user from cookie", %{conn: conn, ets: ets} do
    user = %User{id: 1}
    id   = "test"
    conn =
      conn
      |> store_persistent(ets, id, {[id: user.id], []})
      |> Cookie.call(Cookie.init([]))

    assert Plug.current_user(conn) == user
    assert %{value: new_id, max_age: @max_age, path: "/"} = conn.resp_cookies["persistent_session_cookie"]
    refute new_id == id
    assert PersistentSessionCache.get([backend: ets], id) == :not_found
    assert PersistentSessionCache.get([backend: ets], new_id) == {[id: 1], []}
  end

  test "call/2 assigns user from cookie passing fingerprint to the session metadata", %{conn: conn, ets: ets} do
    user = %User{id: 1}
    id   = "test"
    conn =
      conn
      |> store_persistent(ets, id, {[id: user.id], session_metadata: [fingerprint: "fingerprint"]})
      |> Cookie.call(Cookie.init([]))

    assert Plug.current_user(conn) == user
    assert %{value: new_id, max_age: @max_age, path: "/"} = conn.resp_cookies["persistent_session_cookie"]
    refute new_id == id
    assert PersistentSessionCache.get([backend: ets], id) == :not_found
    assert PersistentSessionCache.get([backend: ets], new_id) == {[id: 1], session_metadata: [fingerprint: "fingerprint"]}
    assert conn.private[:pow_session_metadata][:fingerprint] == "fingerprint"
  end

  test "call/2 assigns user from cookie passing custom metadata to session metadata", %{conn: conn, ets: ets} do
    user = %User{id: 1}
    conn =
      conn
      |> store_persistent(ets, "test", {[id: user.id], session_metadata: [a: 1, b: 2, fingerprint: "fingerprint"]})
      |> Conn.put_private(:pow_persistent_session_metadata, session_metadata: [a: 2])
      |> Conn.put_private(:pow_session_metadata, [a: 3, fingerprint: "new_fingerprint"])
      |> Cookie.call(Cookie.init([]))

    assert Plug.current_user(conn) == user
    assert %{value: id, max_age: @max_age, path: "/"} = conn.resp_cookies["persistent_session_cookie"]
    assert PersistentSessionCache.get([backend: ets], id) == {[id: 1], session_metadata: [fingerprint: "new_fingerprint", b: 2, a: 2]}
    assert [inserted_at: _, b: 2, a: 3, fingerprint: "new_fingerprint"] = conn.private[:pow_session_metadata]
  end

  test "call/2 assigns user from cookie with prepended `:otp_app`", %{config: config, ets: ets} do
    user = %User{id: 1}
    conn =
      :get
      |> ConnHelpers.conn("/")
      |> ConnHelpers.init_session()
      |> Session.call(config ++ [otp_app: :test_app])
      |> store_persistent(ets, "test_app_test", {[id: user.id], []}, "test_app_persistent_session_cookie")
      |> Cookie.call(Cookie.init(config))

    assert Plug.current_user(conn) == user
    assert %{value: new_id, max_age: @max_age, path: "/"} = conn.resp_cookies["test_app_persistent_session_cookie"]
    assert String.starts_with?(new_id, "test_app")
    assert PersistentSessionCache.get([backend: ets], new_id) == {[id: 1], []}
  end

  test "call/2 when user already assigned", %{conn: conn, ets: ets} do
    user = %User{id: 1}
    id   = "test"
    conn =
      conn
      |> store_persistent(ets, id, {[id: user.id], []})
      |> Plug.assign_current_user(:user, [])
      |> Cookie.call(Cookie.init([]))

    assert %{value: new_id, max_age: @max_age, path: "/"} = conn.resp_cookies["persistent_session_cookie"]
    assert new_id == id
    assert PersistentSessionCache.get([backend: ets], id) == {[id: 1], []}
  end

  test "call/2 when user doesn't exist in database", %{conn: conn, ets: ets} do
    user = %User{id: -1}
    id   = "test"
    conn =
      conn
      |> store_persistent(ets, id, {[id: user.id], []})
      |> Cookie.call(Cookie.init([]))

    refute Plug.current_user(conn)
    assert conn.resp_cookies["persistent_session_cookie"] == %{max_age: -1, path: "/", value: ""}
    assert PersistentSessionCache.get([backend: ets], id) == :not_found
  end

  test "call/2 when persistent session cache doesn't have credentials", %{conn: conn} do
    conn =
      conn
      |> persistent_cookie("persistent_session_cookie", "test")
      |> Cookie.call(Cookie.init([]))

    refute Plug.current_user(conn)
    assert conn.resp_cookies["persistent_session_cookie"] == %{max_age: -1, path: "/", value: ""}
  end

  test "call/2 with invalid stored clauses", %{conn: conn, ets: ets} do
    user = %User{id: 1}
    id   = "test"

    assert_raise RuntimeError, "Invalid get_by clauses stored: [id: 1, uid: 2]", fn ->
      conn
      |> store_persistent(ets, id, {[id: user.id, uid: 2], []})
      |> Cookie.call(Cookie.init([]))
    end
  end

  # TODO: Remove by 1.1.0
  test "call/2 is backwards-compatible with just user fetch clause", %{conn: conn, ets: ets} do
    user = %User{id: 1}
    id   = "test"
    conn =
      conn
      |> store_persistent(ets, id, id: user.id)
      |> Cookie.call(Cookie.init([]))

    assert Plug.current_user(conn) == user
    assert %{value: new_id, max_age: @max_age, path: "/"} = conn.resp_cookies["persistent_session_cookie"]
    refute new_id == id
    assert PersistentSessionCache.get([backend: ets], id) == :not_found
    assert PersistentSessionCache.get([backend: ets], new_id) == {[id: 1], []}
  end

  # TODO: Remove by 1.1.0
  test "call/2 is backwards-compatible with `:session_fingerprint` metadata", %{conn: conn, ets: ets} do
    user = %User{id: 1}
    id   = "test"
    conn =
      conn
      |> store_persistent(ets, id, {[id: user.id], session_fingerprint: "fingerprint"})
      |> Cookie.call(Cookie.init([]))

    assert Plug.current_user(conn) == user
    assert %{value: new_id, max_age: @max_age, path: "/"} = conn.resp_cookies["persistent_session_cookie"]
    refute new_id == id
    assert PersistentSessionCache.get([backend: ets], id) == :not_found
    assert PersistentSessionCache.get([backend: ets], new_id) == {[id: 1], session_metadata: [fingerprint: "fingerprint"]}
    assert conn.private[:pow_session_metadata][:fingerprint] == "fingerprint"
  end

  test "create/3 with custom TTL", %{conn: conn, config: config} do
    config = Keyword.put(config, :persistent_session_ttl, 1000)
    conn   = Cookie.create(conn, %User{id: 1}, config)

    assert_received {:ets, :put, [{_key, _value} | _rest], config}
    assert config[:ttl] == 1000

    assert %{max_age: 1, path: "/"} = conn.resp_cookies["persistent_session_cookie"]
  end

  test "create/3 deletes previous persistent session", %{conn: conn, config: config, ets: ets} do
    conn = store_persistent(conn, ets, "previous_persistent_session", {[id: 1], []})

    assert PersistentSessionCache.get([backend: ets], "previous_persistent_session") == {[id: 1], []}

    Cookie.create(conn, %User{id: 1}, config)

    assert_received {:ets, :put, [{_key, {[id: 1], []}}], _config}
    assert PersistentSessionCache.get([backend: ets], "previous_persistent_session") == :not_found
  end

  test "create/3 with `[:pow_session_metadata][:fingerprint]` defined in conn.private", %{conn: conn, config: config} do
    conn
    |> Conn.put_private(:pow_session_metadata, fingerprint: "fingerprint")
    |> Cookie.create(%User{id: 1}, config)

    assert_received {:ets, :put, [{_key, {[id: 1], session_metadata: [fingerprint: "fingerprint"]}}], _config}
  end

  test "create/3 with custom metadata", %{conn: conn, config: config} do
    conn
    |> Conn.put_private(:pow_persistent_session_metadata, session_metadata: [a: 1])
    |> Cookie.create(%User{id: 1}, config)

    assert_received {:ets, :put, [{_key, {[id: 1], session_metadata: [a: 1]}}], _config}
  end
end
