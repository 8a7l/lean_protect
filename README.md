# lean_protect

Lightweight area protection for Luanti servers. Minimal performance
impact even with thousands of areas and players.

## Features

- Two marker tools (stone + stick) for selecting area corners
- `/protect <name>` — create an area
- Protection against dig, place, interact, TNT
- Shared access and ownership transfer
- HUD indicator (area name + owner)
- Golden cube highlight with `/protect_show`
- Crash-safe (leftover walls removed on next start)
- Admin commands with `protection_admin` privilege
- `protection_bypass` privilege for moderators
- Ukrainian localization

## Performance

| Metric | Value |
|---|---|
| Fast path in `core.is_protected` | ~0.3 µs (no areas in chunk) |
| Slow path (area hit) | ~2 µs |
| CPU @ 1000 players, 5000 areas | ~1.3% of one core |
| Memory per area | ~200 bytes |
| Disk write debounce | max 1 write / 2 s |
| Storage shards | 16 (data_0 … data_15) |
| Wall preview cost | 1 VoxelManip call per area |

Key design choices:

- **Spatial hash of chunks** — `is_protected` is O(1) instead of O(N).
- **16 storage shards** — saving one area touches ~1/16 of the data.
- **VoxelManip for walls** — 20× faster than `set_node` for large areas.
- **No globalstep for storage** — uses `minetest.after` debounce.
- **No metadata on temp walls** — zero SQLite writes during preview.

## Installation

1. Extract `lean_protect` into `games/<your_game>/mods/`.
2. Restart Luanti.

Requires Luanti 5.5+ (VoxelManip) and the `default` mod.

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

### Admin commands

Require the `protection_admin` privilege.

| Command | Description |
|---|---|
| `/protect_admin_list <player>` | List areas of any player |
| `/protect_admin_remove <player> <area>` | Force-remove an area |
| `/protect_admin_rename <player> <old> <new>` | Rename any area |
| `/protect_admin_transfer <player> <area> <new_owner>` | Force transfer |
| `/protect_admin_count` | Server-wide stats |

### Privileges

| Privilege | Purpose |
|---|---|
| `protection_admin` | Full access: manage areas, bypass protection, and open containers (chests, furnaces) anywhere. |
| `protection_bypass` | Build access: bypass protection for digging/placing, but **cannot** open containers in foreign areas. |


## Limits

- 3 areas per player
- 10,000 blocks total budget per player
- Minimum 1,000 blocks per area
- No overlap with existing areas

## Storage

Areas are stored in `mod_storage` (SQLite by default) as 16 shards:

```
data_0   data_1   …   data_15     # area data, id % 16
next_id                            # monotonic id counter
schema                             # storage schema version
```

Each shard is a JSON object keyed by string id. Saving one area only
touches its own shard. Legacy single-key storage (`data`) is migrated
automatically on first start of this version.

## Configuration

In `api.lua`:

| Constant | Default |
|---|---|
| `MAX_AREAS_PER_PLAYER` | 3 |
| `MAX_VOLUME_PER_PLAYER` | 10000 |
| `MIN_VOLUME_PER_AREA` | 1000 |

In `storage.lua`:

| Constant | Default |
|---|---|
| `NUM_SHARDS` | 16 |
| `SAVE_INTERVAL` | 2.0 |

## License

GPL-3.0-only. See `LICENSE`.

## Author

8a7l