# Security

This plugin maps SMB/CIFS shares from the Omarchy shell. Plugins run
unsandboxed as the logged-in user. The design below is about keeping SMB
passwords off disk and out of process lists, not about sandboxing the plugin.

## What is stored where

| Data | Location | Notes |
| --- | --- | --- |
| Share label, host, share name, username, domain, automount | `~/.config/omarchy-smb-mapper/shares.json` | Directory `0700`, file `0600`. No password field. |
| Password | libsecret / GNOME Keyring via `secret-tool` | Attributes: `application=omarchy-smb-mapper`, `share-id`, `protocol=smb`. |
| Convenience shortcut | `~/Shares/<label>` | Symlink to the GVFS mount path, created only when that name is free or already this plugin's shortcut. |
| Browse credentials | `$XDG_RUNTIME_DIR/omarchy-smb-mapper/` | Temporary `0600` file, unlinked before the helper returns. |

The plugin does not write `/etc/fstab`, `/etc/samba`, or world-readable
credential files.

## Password handling

- The panel password field is a masked `TextField`.
- The helper receives JSON on stdin. The password is never placed in argv.
- After a successful save, the panel clears the in-memory password field.
- GVFS is told `PasswordSave.NEVER` so it does not keep a second copy. The
  plugin is the only writer into libsecret.
- Guest shares store no secret.

## Privilege boundary

Mounting uses GVFS (`gio` / `python-gobject`) in the user session. The helper
does not request elevated privileges. Unmounting uses `gio mount -u`.

If a share must be a kernel CIFS mount at a custom system path, this plugin is
the wrong tool; keep that in `/etc/fstab` with a root-owned credentials file.

## Untrusted server data

- Browse names from `smbclient` are filtered through the same share-name rules
  as saved shares. Markup and control characters are dropped.
- `smbclient` is run with an 8-second timeout and a 64 KiB output cap.
- Helper errors shown in the panel are truncated plain text, not raw backend
  output.
- QML renders those strings as `Text.PlainText`.

## Shortcuts

`~/Shares/<label>` is replaced only when it is a symlink owned by the current
user, lives directly in that folder, and already points at a GVFS or plugin
runtime path. Ordinary files, directories, and unrelated shortcuts are left
alone.

## Removal

Removing the plugin stops the UI and automount service. It does not wipe the
keyring. Use `secret-tool clear application omarchy-smb-mapper` or Seahorse to
forget saved passwords, and delete `~/.config/omarchy-smb-mapper` if you want
the share list gone too. Do not recursively delete `~/Shares`.

## Marketplace baseline

The repository avoids download-to-shell execution, unpinned remote git
execution, and privileged process control from shared temporary state.
Runtime credential files use `$XDG_RUNTIME_DIR`.
