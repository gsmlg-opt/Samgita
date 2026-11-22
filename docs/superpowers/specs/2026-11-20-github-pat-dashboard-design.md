# GitHub 仓库选择与 Issues / PRs 总览

2026-11-21 · 首版整个 Samgita 实例只配置一个 GitHub PAT，加密保存于 PostgreSQL。多 PAT 与外部密钥管理留给后续版本。

## Settings → GitHub

在现有 Settings 左侧增加 GitHub 分区。操作者粘贴 PAT 并保存，验证成功后显示 GitHub 用户名、连接状态，以及「替换 PAT」「移除连接」操作。所有操作者共享这一条连接和同一份仓库选择。

1. 通过 `GET /user` 确认账号，分页读取 `GET /user/memberships/orgs?state=active` 和 `GET /user/repos`。左侧列出「我的仓库」、账号所属组织和可访问仓库的其他所有者。点选左侧条目后，右侧显示该所有者下当前 PAT 可见的仓库。组织成员身份与仓库可见性分别读取，组织内没有可选仓库时给出空状态。[组织成员关系 API](https://docs.github.com/en/rest/orgs/members#list-organization-memberships-for-the-authenticated-user) · [仓库 API](https://docs.github.com/en/rest/repos/repos#list-repositories-for-the-authenticated-user)
2. 支持按名称搜索、逐个选择仓库，以及选择整个组织。组织按 GitHub 所有者 ID 持续生效。后台刷新发现该组织新增的可见仓库后，总览自动纳入这些仓库。单独勾选的仓库独立保存，取消整组织选择后仍然有效。切换组织、翻页和保存时保留当前位置。如果另一操作者已更改选择，页面保留草稿并提示重新载入。
3. 选择按 GitHub 仓库 ID 保存。仓库改名后更新显示名称。已选仓库若从目录消失，设置页会单独列出，操作者可保留或取消勾选，也能继续添加其他仓库。同一账号替换 PAT 后，按新 PAT 重新确认原有选择的可见性。换成另一账号或移除连接时清空原选择。新 PAT 验证或保存失败时，保留原有连接配置和仓库选择。

细粒度 PAT 的私有仓库访问范围受创建时选定的资源所有者限制。界面按当前 PAT 的实际可见范围展示仓库。[GitHub PAT 说明](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)

首次连接后，Styx 在现有 `hub_github` 队列中读取完整目录。已有连接升级后首次打开设置也会初始化目录。之后打开设置、切换组织和保存选择均读取 PostgreSQL。仓库卡片的刷新图标会排入后台任务；重复点击会合并。任务收到全部分页后一次替换目录，刷新中或读取失败时仍能使用上次成功保存的目录。

## 顶层菜单 GitHub

在主导航增加 **GitHub**，入口为 `/github`。首次访问时，如果还需连接账号或选择仓库，页面给出相应提示和直达 Settings → GitHub 的链接。完成配置后可直接查看所有已选仓库。

| 控件 | 首版行为 |
| --- | --- |
| Overview · `/github` | 按仓库列出打开的 Issue 数和 PR 数。仓库名打开仓库详情，数字打开相应类型的明细。尚未完成首次同步的仓库显示待同步，同步后没有打开条目的仓库显示 0。 |
| 仓库详情 · `/github/repository/:id` | 默认打开 Issues。Pull Requests 和 Workflow Runs 各有独立标签页，可收藏当前标签页的 URL。 |
| Issues · `/github/issue` | 仅显示打开的 Issues，剔除 GitHub Issues 接口同时返回的 PR。 |
| Pull Requests · `/github/pull-request` | 仅显示打开的 PR。 |
| 组织、仓库 | 三个标签页均可按组织和仓库缩小范围。旧书签中的状态参数也沿用只看打开条目的规则。 |
| 列表 | 全局与仓库明细共用表格，显示编号、标题、作者、标签、更新时间和操作。Issue 另有 Type 列。全局表格增加仓库列，点击仓库名进入对应标签页，点击标题打开 GitHub 原文。 |
| 分页与同步 | 页面、筛选和分页直接查询 PostgreSQL。明细按最近更新时间排序。每页均有 Sync 按钮，可立即在 Styx 中排入完整同步。 |

Styx 每 15 分钟同步已选仓库。手动 Sync 与定时任务均以 `state=open` 完整分页读取每个仓库的 Issues 和 PRs。两类数据都读取成功后，同一事务保存打开的条目、将已从打开清单消失的旧条目标记为关闭，并发布同步时间。关闭和合并的条目立即从本地计数和列表消失，重新打开的条目会在下次成功同步时恢复。失败时保留上次成功数据并显示状态。GitHub 返回限流恢复时间时，任务延迟到窗口结束。保存选择或刷新目录发现新的已选仓库时，后台安排首次导入。

Styx 每 15 天清理该连接缓存中已关闭或合并的记录。PostgreSQL 的 `github_pat_connections.next_cleanup_at` 保存下次到期时间。到期后的首个 15 分钟定时任务在一个事务内清理并推进期限，停机跨过多个周期时只需补做一次。

## 仓库详情

- **Issues** 支持复制链接和关闭。点击关闭会弹出确认框，列出目标仓库和编号，确认后才排入任务。关闭成功后当页提供重新打开的按钮，仓库页也可输入编号重新打开此前关闭的 Issue，包括已从本地清理的记录。
- **Pull Requests** 支持复制链接、关闭和提交 Approve 审查。关闭需要二次确认。每行只有一个 Merge 按钮，点击后在确认框中选择创建合并提交或 Rebase and merge，再提交。审查与合并分别由操作者触发，使用页面上显示的 PR head SHA。提交已更新时提示同步。
- **Workflow Runs** 从 PostgreSQL 读取最近 20 条运行。首次打开时 Styx 拉取一页，手动 Sync 刷新当前仓库的运行列表。当前标签页有排队、等待或执行中的运行时，完成一轮刷新后等待 10 秒再通过 Styx 拉取。全部结束或离开该标签页时停止轮询。多个浏览器共享同一个进行中的读取任务。刷新失败时保留上次成功结果。

Issues 和 PRs 直接使用同步响应中的标签名称和颜色。已有标签首次同步前沿用中性底色，有颜色的标签按底色选用黑字或白字。两个表格的操作列都使用图标按钮，鼠标悬停或键盘聚焦时显示操作和目标编号。

仓库详情的 Issue/PR Sync 只刷新当前仓库。操作者的写操作也进入 Styx，由专用 PAT 写入入口提交。发送前记录任务状态，收到不确定结果时提示核对并排入读取，避免重发可能已经生效的操作。成功的状态变化更新本地表格与计数，再同步该仓库。[仓库操作](../../../apps/samgita/lib/samgita/github/pat_actions.ex) · [运行快照](../../../apps/samgita/lib/samgita/github/pat_workflow_runs.ex)

## 数据与凭据

- **连接与选择。** PostgreSQL 保存一条实例级 PAT 连接，含连接 ID、GitHub 账号 ID、登录名、PAT 密文和配置版本。单仓库选择按连接和仓库 ID 唯一，整组织选择按连接和所有者 ID 唯一。目录快照单独存储。Issues 和 PRs 的有效范围取单独选择的仓库与已选组织下当前目录仓库的并集。目录刷新与选择保存分开提交，旧连接或旧任务的返回结果不会覆盖新目录。
- **访问范围。** 控制台选择与 GitHub App 的 Project 映射各自独立。目录、定时同步和 Workflow Runs 使用 GET。手动写入限于上述 Issue/PR 操作，沿用 `SAMGITA_GITHUB_HOSTS` 中批准的 GitHub API 和目标 IP。每次执行核对连接版本、已选仓库和远端条目。`github_pat_repository_syncs` 与 `github_pat_items` 保存总览和明细共用的快照，`github_pat_workflow_snapshots` 单独保存最近运行和同步状态。[现有 GitHub 集成](../../redesign/github-phase-4.md)
- **直接录入 PAT。** 专用输入控件支持 HTTP 和 HTTPS。两种地址使用相同的浏览器端加密格式，随机数来自 `crypto.getRandomValues`，提交入口只接收短期会话票据和密文。服务端验证账号后，以独立用途从部署的 `SECRET_KEY_BASE` 派生密钥，使用随机 nonce 和 AES-256-GCM 加密，密文绑定连接与 GitHub 账号。数据库在同一事务中保存密文和仓库选择。恢复备份需要原运行时密钥，更换该密钥后可在 Settings 重新录入 PAT。将来接入密钥管理时可以沿用连接和仓库 ID。普通 LiveView 事件会把原始参数交给遥测，现有 A11 验收仍为开放项。[PAT 加密](../../../apps/samgita/lib/samgita/github/pat_cipher.ex) · [凭据输入边界](../../codex-app-server/a11-ingress-boundary.md)

## 功能验收场景

计划使用本地模拟 GitHub 和隔离数据库做功能验收。

1. 在两个组织与个人仓库间切换，跨分页勾选并保存。重新打开 Settings，能看到同一份选择。保存和重开均不触发 GitHub 目录请求。点击刷新图标后，新增仓库随其所属的整组织选择自动出现在 Issues 和 PRs 中；只选了个别仓库的组织仍保留原清单。
2. 从主导航打开 GitHub，点击仓库名，在 Issues 与 Pull Requests 标签页之间切换并独立翻页。关闭 Issue 或合并 PR 后成功同步，各入口的计数、分页和列表同步更新，包括带旧状态参数的书签。重新打开 Issue 后同步，它再次出现。浏览 Issue 和 PR 时只读取本地数据。
3. 在仓库数量超过一页、Issue 接口整页只返回 PR、某仓库暂时不可用、连接遇到限流时，列表仍能显示正确的分页、空状态或部分结果。
4. 取消选择一个仓库后刷新总览，该仓库条目消失。移除连接后回到配置引导。桌面与移动端均可走通从选择仓库到打开原文的流程。
5. 通过局域网 HTTP 地址打开 Settings → GitHub，在浏览器没有 `crypto.subtle` 时，表单仍能依次发起会话票据请求和密文提交。可用空输入及模拟响应验证浏览器兼容性。
6. 跨月连续两个 15 天周期，到期前关闭记录仍保存在数据库但已从界面隐藏。到期清理保留打开的 Issues 和 PRs。服务停机后恢复时，定时任务从持久化的期限补做清理。
7. 进入 Workflow Runs，首次同步后展示最近 20 条。排队或运行中的任务触发后续刷新，任务完成或切换标签页后停止。空闲时点击 Sync 可以发现刚开始的运行。
