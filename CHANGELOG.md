# Changelog

## 1.0.1

- Detect GVFS mounts when Samba lowercases the share name.
- Open mounted folders in Files via `uwsm-app` and the `smb://` URI instead of
  treating the GVFS fuse path as a normal directory.
- Document that the plugin never writes `/etc/fstab`.

## 1.0.0

- Add an Omarchy bar widget for saving, mounting, and unmounting SMB shares.
- Store passwords in the user keyring through libsecret, never in plugin config.
- Mount with GVFS so no root privilege is required.
- Create `~/Shares/<label>` shortcuts for connected drives.
- Automount marked shares after login.
