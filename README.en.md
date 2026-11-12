# SuQing's Search Enhancement

Current item identity, visibility and upload status: [workshop-item.json](publishing/workshop-item.json). Frozen manifests under release/ retain their preparation-time state; an old uploaded=false value there does not describe the current Steam item.

Updates reuse the same Workshop item. [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3834692575) · [GitHub source](https://github.com/suching8848/suqing-search-enhancement)

[简体中文](README.md)

The current source is candidate 0.1.4-rc.3 for Project Zomboid B42.21 and B42.22.2 single-player. Search priority and refreshes preserve the visible child selections and Shift anchor of a selected stack in CleanUI 42.22. The Mod ID is `SuQingSearchEnhancement`. Searches scan across frames. The first matches in the current list are highlighted and moved to the top immediately. Further highlights appear as the scan progresses, and stable lists combine nearby priority updates. F8 shows “Searching” during the scan and the final match count after checking container scope and contents. Stable queries reuse text matches, and the pinyin cache evicts individual entries. Reviewed CleanUI paths reuse native order when the list and filters are unchanged. Expanding or collapsing a stack reuses the click's rebuild and keeps matching stacks first on the first frame.

A cold query can take multiple updates to complete. Individual upstream pinyin conversions still run synchronously.

Press **F8** to open the compact panel. Choose Carried or Nearby and look for match markers in existing detailed item lists and container tabs. Enhanced matching rows have purple outlines and the original CleanUI search color for yellow highlighting. Selection and hover retain their original backgrounds while the purple outline continues to mark matches. A badge such as `2/5` appears on the right when only part of a stack matches. When the entire stack matches, the count beside the item name is enough. The inventory context entry is hidden by default; enable it in Mod Options when wanted. Matching item groups move to the top by default, preserving the current order within matching and other groups. Clear the query to restore native order, or disable result priority in Mod Options. Reordering waits during dragging, ordinary mouse holds and marquee selection, then resumes without another item-list click. Supported stack toggles keep matches first.

| Query | Behavior |
| --- | --- |
| `brewing` | Name contains brewing |
| `@"Mod Name" brewing -book` | That source mod, brewing in the name, excluding book |
| `&Chinesecuisine.BrewingBook34` | Exact full item ID with ASCII case-insensitive comparison |
| `wrench \| hammer` | Either group; spaces within a group mean AND |
| `@"Mod Name" "item name"` | Quotes group text containing spaces into one condition; text matching stays tolerant |
| `@vanilla` | Items identified as vanilla by the game |

Names, item type names and source display names support ASCII case-insensitive partial matching with tolerant whitespace, hyphens, underscores and pinyin apostrophes. This does not correct misspellings. Quotes group words into one condition; they do not require exact wording or spacing. Mod IDs after `@` use ASCII case-insensitive literal substring matching. Full item IDs after `&` require ASCII case-insensitive equality and do not use pinyin or separator normalization.

Optional pinyin uses the enabled `yxjs_PinYinSearch` mod; its 1.3 API has been inspected. It provides full spelling, initials and polyphonic alternatives. `NIUROUBING` / `NRB` match 牛肉饼, `M110BQ` matches M110 步枪, and `@SQ` can match source names containing 蘇清. Simplified/traditional character coverage and alternative readings depend on the upstream dictionary; not every character or reading is guaranteed. Homophones can match together: `bianzhi` finds both woven items (编织) and the spoiled status (变质). Use `编织` or `bianzhi -变质` to distinguish them. This mod does not bundle that dictionary. Literal and tolerant case matching remain available when the provider is absent or unavailable.

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

Separately, **Sandbox Options > SuQing's Search Enhancement > Existing search-field handling** selects the world handling mode. This sandbox option is independent of the eight personal Mod Options above. **Handle all searches** is the default, including existing worlds without this value; the mod does not edit the save. **Special syntax only** leaves ordinary words/Chinese names with the existing field's matcher and yellow highlighting. Enhancement activates for `@source`, `&Full.ID`, `-exclusion`, `|`, double quotes or multiple whitespace-separated AND terms. Surrounding whitespace and ordinary hyphens/`@`/`&` inside a name do not trigger it alone. `wrench hammer` is special AND syntax; incomplete special syntax also belongs to the enhanced error display. The independent F8 panel always uses enhanced searching. Set this when creating a world, or through an available existing-world sandbox editor; save and re-enter normally to verify the setting.

CleanUI 2.10.4/2.10.5 inventory fields integrate by default. With the default all-search mode, all nonempty name queries use the enhanced matcher, including ordinary words, full pinyin, initials and combined expressions. In special-only mode, ordinary field input keeps native handling without enhanced outlines, counts or priority. Category mode stays with the existing UI; combined name/category searches still enforce both conditions. Optional left-click popup carries over the text, category and scope. The panel and integrated fields synchronize their text. Disabling integration leaves F8 available for the independent panel. Other inventory UIs can use the common shortcut and inventory context-menu entry; their own text fields require a dedicated adapter.

Nearby reads currently listed, accessible, explored physical containers and visible floor items. Carried reads the main inventory and bags listed by the inventory UI. Proximity Inventory and CleanUI aggregation tabs project readable physical sources with instance-based deduplication. Search does not scan the world, recursively scan bags absent from the UI, open or explore containers, or generate their contents. Input and container events coalesce refreshes. Active queries retain a fallback audit at about one-second intervals, with scanning spread across frames.

Inspected integration targets include vanilla UI, CleanUI 2.10.4/2.10.5, Pinyin Search 1.3, Proximity Inventory and related pinyin, selection and transfer patches. The original transfer, selection and recipe call chains are retained; result priority applies a stable grouping after native sorting and follows NeatUI's actual filtered display list, in-place sorting and list refreshes during rendering. Filtering and sorting changes reapply the grouping. Highlighting and priority sorting support the detailed list view; the icon-grid view is not adapted. Unrecognized custom UI separators retain their segment boundaries, so global priority across those boundaries is not guaranteed.

On 2026-11-08 the user confirmed the reported search hitch was gone and CleanUI stack toggles worked normally in their local B42.21 single-player save. The offline suite passed all 1,253 assertions. Full English UI, controllers, all third-party combinations, other versions and multiplayer still require separate acceptance.

## Installation and acceptance

For local installation, copy the package's `mods/SuQingSearchEnhancement` folder into `%UserProfile%\Zomboid\mods\`, then enable `SuQingSearchEnhancement` in the target save's mod manager. To update an enabled installation, exit the game normally, update that folder and restart. Keep the mod in its own directory. Install and enable the optional pinyin provider separately if wanted.

Use these checks for your own setup; this list is not a claim that every check has already been accepted.

1. Open with F8, type immediately and switch Carried/Nearby. Check original rows, container badges and matching groups at the top.
2. Test source, name, exclusions, OR and exact IDs. Expand mixed-source stacks and verify per-item counts.
3. Select the special-only sandbox mode and re-enter. Enter an ordinary name in a CleanUI field and check original yellow highlighting. Test source, whitespace AND, exclusion and full-ID queries for purple outlines plus yellow highlighting. Check selected/hover backgrounds and the outline. Switch back to all-search mode and check enhanced ordinary-name searching.
4. Edit and clear a CleanUI field, reopen the panel and check text/category synchronization. In special-only mode the F8 panel still enhances ordinary names. Enable click-to-open and test it.
5. Disable integration and use F8. Rebind, save settings and re-enter the game. Toggle result priority and clear the query to check native-order restoration. Close the panel with Escape.
6. Drag an item and release it, then enter `编织` or another carried item name directly in the search field without clicking the item list first. Check that matches move first. Change categories, sort columns and physical/aggregate tabs, then transfer matches and check counts/priority. Check Ctrl/Shift selection, deferred reordering during active dragging/marquee selection, resumption after release and native-order restoration after clearing.
7. Check vanilla/Neat crafting and building magnifier navigation, then inspect English UI, the eight Mod Options and the sandbox option.

Disabling the mod ends its UI features. Queries are session-only; existing world items and save structures require no migration.

## Source and offline checks

Runtime source is under `mods/`. High-resolution cover and separately generated transparent icon, references and exact built-in imagegen prompts are under `art/`. Run `python tools/verify.py` to compile with the game's standalone Kahlua and execute mock item/container/UI regression tests, the native Lua ModOptions implementation, bilingual resource checks and PNG validation. Use `--game-dir` from a separate worktree and `--game-jar` to select a stock JAR for another build. The tool uses the configured local JDK path.

Results are recorded in `validation/result.json`. These checks run offline. Version 0.1.0 completed verified private upload on 2026-11-06, and the user confirmed the 0.1.2 single-player drag-release fix. Source, local installation, frozen packages and publication status are tracked separately in `project.json` and `publishing/workshop-item.json`. Historical freezes retain their preparation-time state.
