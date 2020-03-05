# Configuring mailer

You are able to configure a mailer for Pow and set it up with the library of 
your choice.

This guide shows how to setup Pow with

 * [Swoosh](https://github.com/swoosh/swoosh)
 * [Bamboo](https://github.com/thoughtbot/bamboo)

You must first setup and configure either of these libraries before you can
integrate them with Pow.

## Swoosh mailer

Set up your `WEB_PATH/pow_mailer.ex` file like so:

```elixir
defmodule MyAppWeb.PowMailer do
  use Pow.Phoenix.Mailer
  use Swoosh.Mailer, otp_app: :my_app

  import Swoosh.Email
  
  require Logger

  @impl true
  def cast(%{user: user, subject: subject, text: text, html: html}) do
    %Swoosh.Email{}
    |> to({"", user.email})
    |> from({"My App", "myapp@example.com"})
    |> subject(subject)
    |> html_body(html)
    |> text_body(text)
  end

  @impl true
  def process(email) do
    email
    |> deliver()
    |> log_warnings()
  end

  defp log_warnings({:error, reason}) do
    Logger.warn("Mailer backend failed with: #{inspect(reason)}")
  end

  defp log_warnings({:ok, response}), do: {:ok, response}
end
```

Remember to add `mailer_backend: MyAppWeb.PowMailer` to the Pow configuration, and set the Swoosh configuration:

```elixir
# config/config.exs
config :my_app, :pow,
  user: MyApp.Users.User,
  repo: MyApp.Repo,
  mailer_backend: MyAppWeb.PowMailer

# config/prod.exs
config :my_app, MyAppWeb.PowMailer,
  adapter: Swoosh.Adapters.Sendgrid,
  api_key: "SG.x.x"
```

## Bamboo mailer

Set up your `WEB_PATH/pow_mailer.ex` file like so:

```elixir
defmodule MyAppWeb.PowMailer do
  use Pow.Phoenix.Mailer
  use Bamboo.Mailer, otp_app: :my_app

  import Bamboo.Email

  @impl true
  def cast(%{user: user, subject: subject, text: text, html: html}) do
    new_email(
      to: user.email,
      from: "myapp@example.com",
      subject: subject,
      html_body: html,
      text_body: text
    )
  end

  @impl true
  def process(email) do
    deliver_now(email)
  end
end
```

Remember to add `mailer_backend: MyAppWeb.PowMailer` to the Pow configuration, and set the Bamboo configuration:

```elixir
# config/config.exs
config :my_app, :pow,
  user: MyApp.Users.User,
  repo: MyApp.Repo,
  mailer_backend: MyAppWeb.PowMailer

# config/prod.exs
config :my_app, MyAppWeb.PowMailer,
  adapter: Bamboo.MandrillAdapter, # Specify your preferred adapter
  api_key: "my_api_key" # Specify adapter-specific configuration
```
