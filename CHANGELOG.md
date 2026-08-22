# Changelog

## 1.0.0

- Add an Omarchy bar widget for saving, mounting, and unmounting SMB shares.
- Store passwords in the user keyring through libsecret, never in plugin config.
- Mount with GVFS so no root privilege is required.
- Create `~/Shares/<label>` shortcuts for connected drives.
- Automount marked shares after login.
