# lean_protect

Lightweight area protection for Luanti servers. Minimal performance
impact even with thousands of players.

## Features

- Two marker tools (stone + stick) for selecting area corners
- `/protect <name>` — create an area
- Protection against dig, place, interact, TNT
- Shared access and ownership transfer
- HUD indicator (area name + owner)
- Golden cube highlight with `/protect_show`
- Crash-safe (leftover walls removed on next start)
- Ukrainian localization

## Performance

- **Fast path** in `is_protected`: ~0.3 µs
- **CPU @ 1000 players**: ~1.3% of one core
- **Memory per area**: ~200 bytes
- **Disk writes**: debounced (max every 2 s)

Uses a spatial hash of chunks, so `is_protected` is O(1) instead of O(N).

## Installation

1. Extract `lean_protect` into `games/<your_game>/mods/`.
2. Restart Luanti.

Requires Luanti 5.8+ and `default` mod.

## Usage

### Craft markers

```
Marker #1        Marker #2
[     ]          [     ]
[stick]          [stone]
[stone]          [stick]
```

### Create an area

1. Click marker #1 on one corner.
2. Click marker #2 on the opposite corner.
3. Type `/protect myhome`.

### Commands

| Command | Description |
|---|---|
| `/protect <name>` | Create area from selection |
| `/protect_list` | List your areas |
| `/protect_info` | Show budget |
| `/protect_show [name]` | Highlight area for 15s (all players) |
| `/protect_remove <name>` | Delete an area |
| `/protect_cancel` | Clear selection |
| `/protect_add <area> <player>` | Give access |
| `/protect_remove_member <area> <player>` | Revoke access |
| `/protect_members <area>` | List members |
| `/protect_rename <old> <new>` | Rename |
| `/protect_transfer <area> <player>` | Transfer ownership |
| `/protect_help` | Show all commands |
| `/protect_cleanup` | Remove leftover walls (admin) |

### Limits

- 3 areas per player
- 10,000 blocks total budget
- No overlap with existing areas

## Configuration

In `api.lua`:

| Constant | Default |
|---|---|
| `MAX_AREAS_PER_PLAYER` | 3 |
| `MAX_VOLUME_PER_PLAYER` | 10000 |
| `MIN_VOLUME_PER_AREA` | 1000 |

## License

GPL-3.0-only. See `LICENSE`.

## Author

8a7l