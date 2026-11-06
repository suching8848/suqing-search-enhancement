# Changes / 更新

## 0.1.2 · 2026-11-07

修复拖拽物品结束后直接搜索无法置顶：CleanUI 保留的历史拖拽标记不再阻塞排序，真正的拖拽、鼠标按住和框选仍延后重排。保持既有选择／Shift 锚点、清空恢复及拼音规则。补充真实 CleanUI 鼠标释放函数的离线回归，说明“编织／变质”同音命中。用户于 2026-11-07 确认当前本机 B42.21 单人配置中搜索置顶修复有效。

Restores result priority when searching immediately after releasing a dragged item. CleanUI's retained historical drag flag no longer blocks ordering; active dragging, mouse holds and marquee selection still defer it. Retains selection/Shift anchors, native-order restoration and pinyin rules. Adds offline regression using real CleanUI mouse-release code and documents the 编织/变质 homophone. On 2026-11-07 the user confirmed the search-priority fix works in their current local B42.21 single-player setup.

## 0.1.1 · 2026-11-07

新增独立沙盒选项“原搜索框接管方式”：默认全部接管，可选仅特殊语法。后者让普通原框输入沿用原搜索和黄色高亮，@来源、&完整ID、排除、OR、引号及空格 AND 才触发增强；独立 F8 面板仍始终增强。增强命中使用紫边与原搜索黄色高亮，选中／悬停保留原背景。修复 NeatUI 过滤显示列表、原地排序及绘制中刷新后的匹配置顶失效，并保留拖拽／框选延后重排。八项个人模组设置与沙盒选项独立。此版本尚未上传，待用户游戏内验收；既有 0.1.0 私有上传身份和状态保持。

Adds a separate sandbox handling mode, defaulting to all searches with optional special-syntax-only integration. Ordinary field input then keeps native matching/yellow highlights; source, exact ID, exclusions, OR, quotes and whitespace AND activate enhancement. The independent F8 panel always enhances queries. Enhanced matches use purple outlines plus original yellow search highlighting, retaining selection/hover backgrounds. Repairs priority across NeatUI filtered display lists, in-place sorting and refreshes during rendering while retaining drag/marquee deferral. The eight personal Mod Options remain independent. This update is not uploaded and awaits user gameplay acceptance; the verified private 0.1.0 identity/status is retained.

## 0.1.0 · 2026-11-06

用户于 2026-11-06 反馈当前本机 B42.21 单人功能测试正常，将版本元数据晋级为 0.1.0。产品 Lua 与 0.1.0-rc.3 逐字节一致，本次更新元数据、文档和用户选定的 D「俯视整理桌」系列封面，独立 icon 保持不变。补齐八项设置默认值、通用本地安装步骤，以及详细列表视图、可选上游拼音词典和宽松引号匹配的限制。该反馈不代表英文界面、手柄、所有第三方组合、其他游戏版本、多人／服务器或性能已完成游戏内验收。此段为 0.1.0 的初始准备记录；该版后于 2026-11-06 完成私有上传及原生读回核验，未公开。

On 2026-11-06, the user reported working functionality in their current local B42.21 single-player setup. Version metadata advances to 0.1.0; product Lua remains byte-for-byte identical to 0.1.0-rc.3. This preparation updates metadata, documentation and the user-selected D overhead sorting-desk series cover; the separate icon is retained. Documentation covers all eight defaults, generic local installation, detailed-list support, the optional upstream pinyin dictionary and tolerant quoted-text matching. The feedback does not establish in-game acceptance for English UI, controllers, every third-party combination, other game versions, multiplayer/servers or performance. This describes initial preparation; version 0.1.0 subsequently completed verified private upload and native readback on 2026-11-06. It is not public.

## 0.1.0-rc.3 · 2026-11-06

名称、物品类型名和模组显示名统一支持大小写宽松的部分匹配及常见分隔字符适配。复用原拼音模组的全拼、首字母和多音字候选，补齐 @来源拼音与中英混排；原搜索框中的普通词也统一接入。完整 ID 查询保持大小写忽略的严格匹配。物品栏右键入口默认隐藏，新增独立设置可开启。版本保持原 Mod ID 和已有启用方式，游戏内验收待用户确认。

Unifies case-insensitive, separator-tolerant partial matching for names, type names and source display names. Uses the optional upstream provider for full pinyin, initials and polyphonic alternatives, including @sources and mixed-script names; ordinary queries in integrated fields share the same path. Full IDs retain case-insensitive exact matching. The inventory context entry is hidden by default and can be enabled separately. Mod ID and activation remain consistent; user gameplay acceptance pending.

## 0.1.0-rc.2 · 2026-11-06

匹配组默认置顶，组内物品及两组内部原排序保留；清空或关闭置顶恢复当前原排序。新增双语置顶设置。拖拽、按住鼠标和框选时延后重排，选择与 Shift 锚点按实际绘制行维护。保持当前软件光标配置。离线验证及部署结果见本轮记录，真实游戏内效果待用户确认。

Matching groups appear first by default, retaining item stacks and the current order within both groups. Clearing or disabling priority restores native order. Includes a bilingual priority setting. Reordering waits during dragging, mouse holds and marquee selection; selection and Shift anchors follow actual rendered rows. The current software-cursor setting is retained. See the update receipt for offline validation and deployment; gameplay acceptance is pending user confirmation.

## 0.1.0-rc.1 · 2026-11-06

简洁的随身／附近搜索面板，默认 F8，可设置快捷键、搜索框接入、左键弹出、命中数和用法提示。支持名称、真实来源模组、精确 ID、AND／NOT／OR 与引号。适配 CleanUI，保留原分类条件，并处理 Proximity 汇总及同名堆叠逐件计数。交付中英文本、系列封面和独立透明 icon。离线通过，游戏内验收待用户完成。

Compact carried/nearby panel with F8 default, configurable shortcut, field integration, click popup, counts and hints. Supports names, real source mods, exact IDs, AND/NOT/OR and quotes. Adapts CleanUI with category preservation and per-instance counting across aggregation tabs and mixed stacks. Includes Chinese/English resources, series artwork and a separately generated transparent icon. Offline checks passed; user gameplay acceptance pending.
