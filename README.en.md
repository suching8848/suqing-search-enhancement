# SuQing's Search Enhancement

Workshop item: [uploaded and verified private item](https://steamcommunity.com/sharedfiles/filedetails/?id=3834692575). Source repository: [suching8848/suqing-search-enhancement](https://github.com/suching8848/suqing-search-enhancement). Private upload and native content readback completed on2026-11-06. The item is not public; gameplay acceptance is unchanged.

[简体中文](README.md)

Version 0.1.0 targets Project Zomboid B42.21 single-player. Mod ID `SuQingSearchEnhancement`. On 2026-11-06, the user reported that the functionality worked in their current local B42.21 single-player setup. This version is prepared locally and has not been uploaded to Workshop. Product Lua is byte-for-byte identical to 0.1.0-rc.3.

Press **F8** to open the compact panel. Choose Carried or Nearby and look for purple markers in existing detailed item lists and container tabs. A stack badge such as `2/5` means two matching items. The inventory context entry is hidden by default; enable it in Mod Options when wanted. Matching item groups move to the top by default, preserving the current order within matching and other groups. Clear the query to restore native order, or disable result priority in Mod Options. Reordering waits during dragging, mouse holds and marquee selection.

| Query | Behavior |
| --- | --- |
| `brewing` | Name contains brewing |
| `@"Mod Name" brewing -book` | That source mod, brewing in the name, excluding book |
| `&Chinesecuisine.BrewingBook34` | Exact full item ID with ASCII case-insensitive comparison |
| `wrench \| hammer` | Either group; spaces within a group mean AND |
| `@"Mod Name" "item name"` | Quotes group text containing spaces into one condition; text matching stays tolerant |
| `@vanilla` | Items identified as vanilla by the game |

Names, item type names and source display names support ASCII case-insensitive partial matching with tolerant whitespace, hyphens, underscores and pinyin apostrophes. This does not correct misspellings. Quotes group words into one condition; they do not require exact wording or spacing. Mod IDs after `@` use ASCII case-insensitive literal substring matching. Full item IDs after `&` require ASCII case-insensitive equality and do not use pinyin or separator normalization.

Optional pinyin uses the enabled `yxjs_PinYinSearch` mod; its 1.3 API has been inspected. It provides full spelling, initials and polyphonic alternatives. `NIUROUBING` / `NRB` match 牛肉饼, `M110BQ` matches M110 步枪, and `@SQ` can match source names containing 蘇清. Simplified/traditional character coverage and alternative readings depend on the upstream dictionary; not every character or reading is guaranteed. This mod does not bundle that dictionary. Literal and tolerant case matching remain available when the provider is absent or unavailable.

Source matching uses the real Mod ID and loaded mod display name. Script namespaces such as `Base` and Workshop item IDs are distinct from the source Mod ID. One item must satisfy an entire group. Incomplete syntax clears previous markers and shows a localized hint.

Open **Options > Mod Options > SuQing's Search Enhancement** to configure these eight settings. The settings API is part of the game, and the core has no external prerequisite. These are first-use defaults; saved user settings take precedence.

| Setting | Default |
| --- | --- |
| Integrate supported inventory search fields | On |
| Open the panel by left-clicking a search field | Off |
| Panel shortcut | F8 |
| Show container hit counts and matching stack counts | On |
| Expand usage hints when first opening the panel | Off |
| Pinyin matching, when an upstream provider is available | On |
| Move matching results to the top | On |
| Show the inventory context-menu entry | Off |

The context-menu setting takes effect when the menu is next opened. The panel shortcut is suspended during text entry.

CleanUI 2.10.4 inventory fields integrate by default. All nonempty name queries use the enhanced matcher, including ordinary words, full pinyin, initials and combined expressions. Category mode stays with the existing UI; combined name/category searches still enforce both conditions. Optional left-click popup carries over the text, category and scope. The panel and integrated fields synchronize their text. Disabling integration leaves F8 available for the independent panel. Other inventory UIs can use the common shortcut and inventory context-menu entry; their own text fields require a dedicated adapter.

Nearby reads currently listed, accessible, explored physical containers and visible floor items. Carried reads the main inventory and bags listed by the inventory UI. Proximity Inventory and CleanUI aggregation tabs project readable physical sources with instance-based deduplication. Search does not scan the world, recursively scan bags absent from the UI, open or explore containers, or generate their contents. Input/container events coalesce refreshes, with a one-second fallback while a query is active.

Inspected integration targets include vanilla UI, CleanUI 2.10.4, Pinyin Search 1.3, Proximity Inventory and related pinyin, selection and transfer patches. The original transfer, selection and recipe call chains are retained; result priority applies a stable grouping after native sorting. Highlighting and priority sorting support the detailed list view; the icon-grid view is not adapted. Unrecognized custom UI separators retain their segment boundaries, so global priority across those boundaries is not guaranteed.

The user reported working functionality in their current local B42.21 single-player setup. This does not establish in-game acceptance for the English interface, controllers, every third-party combination, other game versions, multiplayer/servers or performance. Those require separate validation.

## Installation and acceptance

For local installation, copy the package's `mods/SuQingSearchEnhancement` folder into `%UserProfile%\Zomboid\mods\`, then enable `SuQingSearchEnhancement` in the target save's mod manager. To update an enabled installation, exit the game normally, update that folder and restart. Keep the mod in its own directory. Install and enable the optional pinyin provider separately if wanted.

Use these checks for your own setup; this list is not a claim that every check has already been accepted.

1. Open with F8, type immediately and switch Carried/Nearby. Check original rows, container badges and matching groups at the top.
2. Test source, name, exclusions, OR and exact IDs. Expand mixed-source stacks and verify per-item counts.
3. Edit and clear a CleanUI field, reopen the panel and check text/category synchronization. Enable click-to-open and test it.
4. Disable integration and use F8. Rebind, save settings and re-enter the game. Toggle result priority and clear the query to check native-order restoration. Close the panel with Escape.
5. Transfer matching items, switch between physical and aggregate tabs and walk away. Check Ctrl/Shift selection, dragging and batch transfers.
6. Check vanilla/Neat crafting and building magnifier navigation, then inspect the interface and settings in English.

Disabling the mod ends its UI features. Queries are session-only; existing world items and save structures require no migration.

## Source and offline checks

Runtime source is under `mods/`. High-resolution cover and separately generated transparent icon, references and exact built-in imagegen prompts are under `art/`. Run `python tools/verify.py` to compile with the game's standalone Kahlua and execute mock item/container/UI regression tests, the native Lua ModOptions implementation, bilingual resource checks and PNG validation. Local game/JDK paths are configured in that tool.

Results are recorded in `validation/result.json`. These checks do not start the game or load a save. Actual UI, gameplay and performance acceptance are tracked separately. Project delivery records distinguish source, local installation, frozen packages and publication state. Version 0.1.0 is prepared locally and has not been uploaded to Workshop.
