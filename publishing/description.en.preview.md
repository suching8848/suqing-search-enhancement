# SuQing's Search Enhancement

Search logic inspired by Minecraft JEI. Find carried and nearby items by name, source mod, full item ID and optional pinyin. Highlight matches, show per-item counts and prioritize matching groups in existing detailed inventory lists.

**Opening and settings**
Press F8 to open the enhanced panel; the shortcut is configurable. Choose Carried or Nearby, insert query conditions and view usage hints. CleanUI 2.10.4 inventory fields integrate by default. Toggle this under Options > Mod Options > SuQing's Search Enhancement. Clicking an existing field to open the panel is off by default. The inventory context-menu entry is also hidden by default and can be enabled separately.
Field integration, counts, result priority and available pinyin default to on. Click popup, expanded help and the context entry default to off. The core uses the game's built-in PZAPI/ModOptions and has no external hard requirement.

**Query examples**
brewing: partial name match.
@"Mod Name" brewing -book: source AND name, excluding book.
&Chinesecuisine.BrewingBook34: exact full item ID, ignoring ASCII letter case.
wrench | hammer: either group; spaces within each group mean AND.
"item name": quotes combine text containing spaces into one condition.
@vanilla: items identified as vanilla by the game.
Names, item type names and source display names ignore ASCII case and tolerate whitespace, hyphens, underscores and pinyin apostrophes. There is no spelling correction. Full IDs never use partial or pinyin matching. @ModID uses the actual ID. Quotes do not enforce exact whitespace.

**Optional integrations**
[Pinyin Search (yxjs_PinYinSearch 1.3)](https://steamcommunity.com/sharedfiles/filedetails/?id=3657184750): when enabled, supplies full spelling, initials and polyphonic alternatives, limited by its dictionary and pronunciation coverage. For example, NIUROUBING / NRB can find 牛肉饼 and M110BQ can find M110 步枪. Literal search remains available without it. Its code and dictionary are not bundled.
[CleanUI 2.10.4](https://steamcommunity.com/sharedfiles/filedetails/?id=3437629766): adapts supported inventory fields, retains category conditions and synchronizes panel text and scope. Other UIs can use the F8 panel; their own fields require an adapter.
[Proximity Inventory](https://steamcommunity.com/sharedfiles/filedetails/?id=2847184718): supports projections of listed, readable physical sources with instance-based deduplication.
These integrations are optional; installing all of them is unnecessary.

**Scope, compatibility and removal**
Targets Build 42.21 single-player. Highlighting and priority target detailed lists; icon-grid rendering is not adapted. Carried covers the main inventory and bags listed by the UI. Nearby reads listed, accessible, explored containers and visible floor items. It does not scan the world, inspect unexplored containers or generate loot.
Priority preserves current order within matching and other groups. Clear the query or disable priority to restore native order. Reordering waits during dragging, mouse holds and marquee selection. Items and save structures are unchanged; queries are session-only. Exit normally, disable the mod and restart to remove its UI behavior. Manual and Workshop copies share one Mod ID; keep one loading source.

**Validation and assets**
On 2026-11-06 the user reported normal search functionality in their current local B42.21 single-player setup. Version 0.1.0 retains the exact functional Lua files from that tested rc.3; this preparation updates metadata and release materials. Offline checks include 864 regression assertions, Chinese/English resources and image checks. No claim is made for tested multiplayer, other versions, every third-party combination, complete English UI gameplay acceptance or measured performance gains.
The cover and separately created transparent icon use AI-assisted artwork. The promotional character is not an in-game skin or outfit. Thanks to the optional integration authors; upstream projects remain their authors' work.

Mod ID: SuQingSearchEnhancement
