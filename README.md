# shop

A Roblox shop / loadout system built with [Rojo](https://github.com/rojo-rbx/rojo) 7.6.1. Players can browse weapon categories, purchase weapons with credits, and build saved loadouts (sets of owned weapons with a weight budget) that are equipped on spawn.

## Project layout

Rojo maps `src/` into the DataModel (see `default.project.json`):

| Source path        | In-game location                | Purpose                                            |
| ------------------ | ------------------------------- | -------------------------------------------------- |
| `src/server`       | `ServerScriptService.ShopServer` | Server-side query, purchase, and loadout logic     |
| `src/shared`       | `ReplicatedStorage.ShopClient`   | Types, UI modules, scoring, client entry helpers   |
| `src/storage`      | `ServerStorage.ShopStorage`      | Weapon catalog: one `ItemInfo` module per weapon   |
| `src/client`       | `StarterPlayer.StarterPlayerScripts` | Client entrypoint that detects shop/loadout zones |

The server also depends on a `DataAPI` (in `ServerScriptService.DataAPI`) and shared `ShopRemotes` / `ShopBindables` / `WeaponPreview` / `GUIs` instances that live in the place file.

## Server

Everything boots from `src/server/init.server.luau`, which loads three systems:

- **`Queries.luau`** — reads the weapon catalog and answers item lookups.
- **`Purchases.luau`** — buys items, validates cost/level/ownership, decrements credits.
- **`Loadouts.luau`** — saves/validates loadouts and equips them on spawn.

### Weapon catalog (`src/storage/ItemInfo`)

Weapons are plain modules grouped into `Gun` and `Melee` folders. Each module returns a `WeaponInfo` table (see `src/shared/ShopTypes.luau`), e.g.:

```lua
return {
    Name = "M4A1",
    Category = "Gun",
    Weight = "Moderate",   -- "Light" | "Moderate" | "Heavy"
    Price = 10000,
    Level = 0,
    Lore = 'The true OG of the automatic weapons. Please send an "Amen"',
    PreviewImage = "rbxassetid://135678735388202",
    ItemInfo = { DamageType = "Bullet" },
    Pills = {},
}
```

On load, `Queries` requires every module and builds in-memory indexes:
- `MODULE_INFOS` — by module name
- `MODULE_INFOS_BY_LOOKUP_KEY` — by normalized name (whitespace/punctuation stripped, case-insensitive)
- `MODULES_BY_CATEGORY` — by `Category`

### Query pipeline

`Queries` exposes one big `ShopQuery` type (also in `ShopTypes`) that flows through the following stages:

1. **Filtering** (`passesBaseFilters`) — `nameContains`, `search` (name or lore), `weights`, `priceMin/Max`, `levelMin/Max`, `consumable`, `groupUnlocked`, and arbitrary `customFilters`. Keys prefixed with `ItemInfo.` filter into the nested `ItemInfo` table.
2. **Sorting** (`applySort`) — by any top-level or `ItemInfo.*` field, ascending/descending (`sortDir`), defaulting to `Name`. Values are normalized by type so numbers/strings/booleans sort sensibly; `Name` is the tie-breaker.
3. **Pagination** (`applyPagination`) — `offset` / `limit`.
4. **Projection** (`projectInfo` + `returnType`) — optionally return only the listed `fields`, as an array or keyed-by-`Name` map.

### Remote / bindable API

| Remote (`ReplicatedStorage.ShopRemotes`) | Signature | Returns |
| --- | --- | --- |
| `GetWeaponInfo` | `(name or query)` | A single `WeaponInfo` (or projected fields) |
| `GetAllInfoForCategory` | `(category or query)` | `WeaponInfo[]` / `{[string]: WeaponInfo}` |
| `GetOwnedItems` | `()` | Owned item names (server-side, 2s cache) |
| `GetGunSettings` / `GetMeleeSettings` | `(name)` | Live gun/melee stat settings from `WeaponPreview` |
| `RequestPurchase` | `(itemName)` | `success, message` |
| `ItemPurchased` | — | Server→client event fired after a successful purchase |
| `ValidateLoadout` / `GetPlayerLoadouts` / `RemoveLoadout` / `SetActiveLoadout` / `RequestLoadout` | — | Loadout CRUD and equipping |

The same lookup logic is re-exposed through `ServerStorage.ShopBindables` (`GetPlayerOwnedItems`, `GetWeaponInfo`, `GetAllInfoForCategory`, `SetActiveLoadout`) so server-side systems can query without a remote. All calls pass through the `InvokeLogger` helper, which counts and optionally logs every invoke.

### Purchasing

`Purchases` validates each request server-side (item exists, credits ≥ price, level ≥ required, badge/group requirement met), then atomically decrements credits via `DataAPI.incrementPlayerInfo` and adds the item to the player's owned inventory. It invalidates the owned-items cache and fires `ItemPurchased` back to the client. The client's own checks are only for UX — the server is the source of truth.

### Loadouts

`Loadouts` stores named loadouts (arrays of item names, `"None"` for empty slots) per player via `DataAPI`. It:

- Loads a gamemode-specific `LoadoutConfig` (`LoadoutConfigs.Survival` or `Sandbox`) from the `Gamemode` workspace attribute, which defines `maxSlots`, `maxWeight`, and per-weight-tier costs.
- **Validates** every save/equip (layer 1: all items owned, no duplicates, valid names; layer 2: slot count and total weight fit the config).
- Sanitizes loadout names (trim, length ≤ 32, whitelisted characters, Roblox text moderation).
- Throttles `RequestLoadout` to one call per 5 seconds (bypassable server-side for spawns).
- On player spawn, clones the tools for the active loadout from `ServerStorage.ShopWeapons` into the backpack.

## Client

The client is driven by `src/client/init.client.luau`. It waits for the `Shops` and `LoadoutAreas` workspace zones, and when the local character enters a trigger, it disables movement/music and opens the UI:

- **Shop zones** open the shop UI for that specific shop model (e.g. the Gun Shop).
- **Loadout zones** open the loadout editor.
- Leaving is driven by the `InShop` player attribute (set false on close).

### `ReplicatedStorage.ShopClient.UI` — screen modules

The single screen controller is **`SLSGui.luau`** (in `ShopClient/UI`):

- Clones the `GUIs.SLSGui` root screen and manages three sub-states — **Shop**, **Loadout**, and **Stats** — with a top-level options menu and fade/transition handling.
- On construction it kicks off a background task that pre-fetches **all** weapon info, gun/melee settings, and owned items through `CollectInfoLibrary()`. The result is an `InfoLibrary` (typed in `ShopTypes`) handed to each sub-screen. It provides `getWeaponInfo`, `getAllForCategory`, `queryWeapons`, `getGunSettings`, `getMeleeSettings`, `getOwnedItems`, `isOwned`, `refreshOwnedItems`, and `registerOwnedItem` — so screens share one cached view of the catalog and never re-query per frame.
- Owns shared polish: sound effects (`SOUND_MAP`), button hover/scale tweens, core-GUI hiding, and the `AdaptiveMusic` song.

**`Shop.luau`** — the purchase UI (screen layout in `GUIs.Shop`):

- **WeaponSelection** (left): a scrolling list of weapon buttons cloned from a `Reference`, showing preview image, price (`※`), and required level. Each button's state (green = owned, red = locked, greyed out) is driven by `ApplyWeaponFrameState`.
- **Filters** (top-left): weight pills (Light/Moderate/Heavy) built from the shop's `ShopInfos.<ShopName>` config; cycling them calls `infoLibrary.queryWeapons`.
- **WeaponPreview** (center): a `ViewportFrame` that clones the weapon model from `ReplicatedStorage.WeaponPreview`, spins it on `RenderStepped`, and offsets the camera per-item (`PreviewCameraOffset`).
- **WeaponInfo / Lore / PurchaseArea** (right): weapon name, lore, `SpecialText`, and the purchase button. `ApplySelectedWeaponState` reflects owned/locked/affordable states.
- **WeaponStats** (right-bottom): stat bars and pills generated from `GunScoring`/`MeleeScoring` (0–1 scores vs. baselines) plus the weapon's own `Pills` tags; damage types get color-coded pills.
- Purchases invoke `RequestPurchase`, play sounds, animate the currency counter down, and refresh owned state from the `ItemPurchased` event.
- Camera work: scriptable camera locked to the shop's `CameraPart`, mouse-parallax lerp, blur + tint tweens, and the player character is locked in place.

**`Loadout.luau`** — the loadout editor (layout in `GUIs.Loadout`):

- A **character preview** (`LoadoutCharacter` model cloned into the workspace) that welds the currently selected weapon onto the right arm, plays equip/idle animations from the weapon's `Setting`/`Animations`, and plays equip sounds.
- **WeaponSlots**: `maxSlots` slots cloned from a `Reference`. Clicking a slot opens the **WeaponSelection** panel; double-click or right-click unequips. Equipping enforces the config weight budget (`CanEquipWeaponInSlot`, weight bar with a predicted-fill overlay while hovering).
- The weapon picker lists only **owned** items (refreshed lazily), with search + weight toggles and a dimmed "already equipped" state.
- **LoadoutArea**: saved loadouts as a scroll list with a remove button, a name textbox + add button, and a status message. Saving invokes `ValidateLoadout`; deleting invokes `RemoveLoadout`; making a loadout active calls `SetActiveLoadout`.
- On exit it fires `RequestLoadout` (throttled server-side) so the equipped loadout is actually given to the player.

**`Stats.luau`** — a placeholder stats screen with an exit button (most content lives in the place file's `GUIs.Stats`).

### Shared client-support modules

- `ShopTypes.luau` — all exported types (`WeaponInfo`, `ShopQuery`, `Loadout`, `LoadoutConfig`, `InfoLibrary`, etc.).
- `InvokeLogger.luau` — wraps `InvokeServer`/`BindableFunction` calls with counting and optional logging.
- `GunScoring.luau` / `MeleeScoring.luau` — convert raw weapon stats into 0–1 bar fills for the shop UI.
- `AnimationHandler.luau` — loads and manages animation tracks on the loadout preview character.
- `LoadoutHandler.luau` — small helper to validate/save a loadout from slot data.
- `ShopInfos/` — per-shop display config (category + filter pills).
- `LoadoutConfigs/` — per-gamemode loadout rules (`maxSlots`, `maxWeight`, per-weight-tier costs).

## Getting started

Build and open the place in Roblox Studio, then start the Rojo server:

```bash
rojo build -o "shop.rbxlx"
rojo serve
```

For more help, check out [the Rojo documentation](https://rojo.space/docs).
