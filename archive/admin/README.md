# admin (archived)

Frozen snapshot of the stow package for the main/admin macOS account. It is
kept here for reference only until it moves to its own repository; nothing
in `packages/`, `bootstrap.sh`, or the manifests depends on it.

The admin account is intentionally minimal: no Homebrew, no language
runtimes, no dev tooling. Just `.zshrc`, `.zprofile` (with the `dev-shell`
helper that `ssh`es into the isolated dev account), and `.macos` for one-time
system-wide keyboard/typing defaults.

## Deploy (from this archive)

```bash
./prepare-stow-targets.sh archive/admin ~
stow -d archive -t ~ admin
```

## Setting up `dev-shell` (SSH, not `su`)

`dev-shell` uses `ssh claude@127.0.0.1` (override with `DEV_USER`), not `su`.
`su` keeps the dev shell as a descendant of the admin account's own
Terminal.app process, and macOS resolves Apple Event "responsible process"
permissions by walking up that ancestry — so a process running as the dev
user can send unprompted AppleScript to the admin's Terminal.app (e.g.
`do script "..."` runs as the admin account: a full privilege escalation out
of the isolated account). `ssh` forks a fresh process tree via `sshd` with no
Terminal.app ancestor, closing this off entirely. One-time setup, on the
**admin** account:

```bash
# 1. Enable Remote Login, restricted to the dev account only
sudo systemsetup -setremotelogin on
sudo dseditgroup -o edit -a claude -t user com.apple.access_ssh

# 2. Generate a key pair for the admin account (on this machine, not copied
#    in from elsewhere) and authorize it for the dev account
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_dev -N ""
ssh-copy-id -i ~/.ssh/id_ed25519_dev.pub claude@127.0.0.1

# 3. Require key-based auth only (edit /etc/ssh/sshd_config as root)
sudo tee -a /etc/ssh/sshd_config <<'EOS'
Match User claude
    PasswordAuthentication no
EOS
sudo launchctl kickstart -k system/com.openssh.sshd
```

Then `dev-shell` (from `.zprofile`) just works: `ssh -t claude@127.0.0.1`.
If the dev account has a different name, `export DEV_USER=<name>` in the
admin shell.

Note: use `127.0.0.1`, not `localhost` — macOS's `sshd_config` ships with
`ListenAddress 127.0.0.1` (IPv4 only), so if `localhost` resolves to `::1`
first on your machine, the connection will fail even with everything else
configured correctly.
