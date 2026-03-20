# XDG for Zig

XDG libraries for Zig

## XDG Desktop Entry

XDG Desktop Entry file format library for Zig.

## Specification reference

Revised against version 1.5 published on 2020-04-27.

- <https://specifications.freedesktop.org/desktop-entry/latest/>
  - <https://xdg.pages.freedesktop.org/xdg-specs/desktop-entry/latest-single/>
- <https://wiki.archlinux.org/title/Desktop_entries>

## XDG Base Directory

Cross-platform implementation of the XDG Base Directory specification.

Current behavior highlights:

- Supports XDG_DATA_HOME, XDG_CONFIG_HOME, XDG_STATE_HOME, XDG_CACHE_HOME,
  XDG_DATA_DIRS, and XDG_CONFIG_DIRS.
- Relative values in XDG environment variables are treated as invalid and
  ignored.
- XDG_DATA_DIRS and XDG_CONFIG_DIRS use the platform PATH separator:
  - Linux/macOS: :
  - Windows: ;
- XDG_RUNTIME_DIR rules:
  - Absolute value is accepted.
  - Relative value is rejected.
  - On Linux, when unset or invalid, fallback is /run/user/$UID.
  - On non-Linux platforms, unset or invalid resolves to null.

Module location:

- src/lib/base_directory/root.zig

Base Directory specification reference:

- <https://specifications.freedesktop.org/basedir-spec/latest/>
- <https://xdg.pages.freedesktop.org/xdg-specs/basedir-spec/latest/>

## Credits

- [PyXDG](https://www.freedesktop.org/wiki/Software/pyxdg/)
