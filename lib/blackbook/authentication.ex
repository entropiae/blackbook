defmodule Blackbook.Authentication do
  @moduledoc """
  Handles core authentication "stuff" - verifying who the user is,resetting information etc.
  """

  use Timex

  @doc """
  Each user is granted a single token login at registration. This method uses that unique token to log them in.


  ## Examples

  ```
  {:ok, user} = Blackbook.Authentication.authenticate_by_token 'BIGLONGTOKEN'
  ```
  """
  def authenticate_by_token(token) do
    login = Blackbook.Repo.get_by(Blackbook.Login, provider_key: "token", provider: "token", provider_token: token)
    case login do
      nil -> {:error, "That token is invalid"}
      login -> pull_user_record({:ok, login})
              |> ensure_status_allows_login
              |> log_it
    end
  end

  @doc """
  The core "login" method that takes an email and password.

  ## Examples

  ```
  {:ok, user} = Blackbook.Authentication.authenticate_by_email_password 'test@test.com', 'password'
  ```
  """
  def authenticate_by_email_password(email, password) do
    locate_login_by_email(email)
      |> verify_password(password)
      |> pull_user_record
      |> ensure_status_allows_login
      |> log_it
  end

  @doc """
  Changes the user's password.

  ## Examples

  ```
  {:ok, user} = Blackbook.Authentication.change_password 'test@test.com', 'password', 'new_password'
  ```

  """
  def change_password(email, old_password, new_password) do
    locate_login_by_email(email)
      |> verify_password(old_password)
      |> reset_password(new_password)
  end

  @doc """
  Returns a password reminder token the user can use to validate against and then reset their password. Expires in 24 hours.

  ## Examples

  ```
  token = Blackbook.Authentication.get_reminder_token 'test@test.com'
  ```

  """
  def get_reminder_token(email) do
    Blackbook.User.find_by_email(email)
      |> reset_reminder_token
  end

  @doc """
  Validates a password reset token by 1) making sure it exists and 2) making sure it isn't expired. The user record is returned.

  ## Examples

  ```
  {:ok, user} = Blackbook.Authentication.validate_password_reset 'test@test.com'
  ```
  """
  def validate_password_reset(token) do
    found = Blackbook.User.find_by_reset_token(token)
    case found do
      nil -> {:error, "That token is invalid"}
      user -> {:ok, user}
    end
  end


  @doc """
  Each user has a random user key assigned to them at registration. This is a good candidate for use as a session key.

  ## Examples

  ```
  {:ok, user} = Blackbook.Authentication.get_user 'MY_USER_KEY'
  ```
  """
  def get_user(key) do
    found = Blackbook.User.find_by_key(key)
    case found do
      nil -> {:error, "That user key is invalid"}
      user -> {:ok, user}
    end
  end

  # ===================================================================================== Privvies



  defp reset_reminder_token(nil), do: {:error, "This email does not exist"}
  defp reset_reminder_token(user) do

    new_token = SecureRandom.urlsafe_base64()
    expiration = Date.now |> Date.add(Time.to_timestamp(1, :days))

    changeset = Blackbook.User.changeset(user,%{password_reset_token: new_token, password_reset_token_expiration: expiration })

    case Blackbook.Repo.update changeset do
      {:ok, user} -> {:ok, user.password_reset_token}
      {:error, err} -> {:error, err}
    end
  end
  defp reset_password({:error, err}, new_password), do: {:error, "This login does not exist in our system."}
  defp reset_password({:ok, login}, new_password) do
    case Blackbook.Util.hash_password new_password do
      {:ok, hashed} ->
        changeset = Blackbook.Login.changeset(login, %{provider_token: hashed})
        Blackbook.Repo.update changeset

      {:error, err} -> {:error, err}
    end
  end

  defp locate_login_by_email(email) do
    #get the user
    case Blackbook.User.find_login(email) do
      nil -> {:error, "This email doesn't exist in our system"}
      login -> {:ok, login}
    end
  end

  defp verify_password({:error, err}, password), do: {:error, err}
  defp verify_password({:ok, login}, password) do
    case Comeonin.Bcrypt.checkpw(password, login.provider_token) do
      true -> {:ok, login}
      false -> {:error, "That password is invalid"}
    end
  end

  defp pull_user_record({:error, err}), do: {:error, err}
  defp pull_user_record({:ok, login}) do
    {:ok, Blackbook.Repo.get(Blackbook.User, login.user_id)}
  end

  defp ensure_status_allows_login({:error, err}), do: {:error, err}
  defp ensure_status_allows_login({:ok, user}) do
    case user.status do
      "active" -> {:ok, user}
      _ -> {:error, "This account is currently denied access"}
    end
  end

  defp log_it({:error, err}), do: {:error, err}
  defp log_it({:ok, user}) do
    Blackbook.Repo.transaction fn ->
      #add a log entry
      Blackbook.Repo.insert %Blackbook.UserLog{user_id: user.id, subject: "Authentication", entry: "User #{user.email} logged in"}

      #set the last login
      changeset =Blackbook.User.changeset(user, %{last_login: Ecto.DateTime.local()})
      case Blackbook.Repo.update changeset do
        {:ok, user} -> user
        {:error, err} -> {:error, err}
      end
      user
    end
  end

end
