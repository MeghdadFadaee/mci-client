# MCI Internet Packages Client

Rust client for fetching unused internet package bytes from the MCI
(`my.mci.ir`) API.

## Features

- Login and refresh-token handling
- Reuses valid saved sessions
- Stores refreshed tokens in `.env`
- Retries package fetches once after a 401 response
- Extracts every `unusedAmount` value from the response tree
- Runs as a terminal-less Windows tray app
- Shows startup, credential, network, and API errors inside the overlay label
- Provides tray actions for Manage App, Reload, Reset Session, and Quit

## Requirements

- Rust 1.95+
- Internet access to `https://my.mci.ir`

## Environment

Create a `.env` file:

```env
MCI_USERNAME="9123456789"
MCI_PASSWORD="your_password"

MCI_ACCESS_TOKEN=""
MCI_REFRESH_TOKEN=""
MCI_SESSION_STATE=""
MCI_ACCESS_TOKEN_EXPIRES_AT=""
MCI_REFRESH_TOKEN_EXPIRES_AT=""

PULL_INTERVAL_SECONDS=10

MCI_LABEL_FONT_FAMILY="IRANSansWeb"
MCI_LABEL_FONT_SIZE=14
```

## Build

```bash
cargo build --release
```

## Installers

Tagged GitHub releases build Windows artifacts automatically:

- `mci-client-<version>-windows-x64-portable.zip`
- `mci-client-<version>-windows-x64-setup.exe`
- `mci-client-<version>-windows-x64.msi`
- `mci-client-<version>-windows-x64-setup-bundle.zip`

Create a release by pushing a tag like `v0.1.0`.

## Usage

Build and run the app:

```bash
cargo build --release
target\release\mci-client.exe
```

The app starts as a floating always-on-top label and adds a tray icon. Use the
tray menu to manage it:

- Manage App: edit username, password, pull interval, label font, and label size
- Reload: fetch package data immediately
- Reset Session: clear saved tokens, then fetch again
- Quit: exit the app

Options:

```bash
cargo run --release -- --interval 30 gui
cargo run --release -- --env path\to\.env gui
```

If no command is provided, `gui` is used by default.

## Notes

- The MCI API may require an Iranian IP address and the browser-like headers
  used by this client.
- Tokens are written back to `.env` with a 30-second expiry safety buffer.
- GUI and tray mode are implemented with native Win32 APIs.
- `icon.ico` is loaded for the window and tray icon at runtime. The build also
  embeds it into the executable when the Windows SDK `rc.exe` tool is available.

## License

MIT
