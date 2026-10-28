# RouterOS 管理登录失败封禁

## 1. 项目介绍

最低版本要求为 **RouterOS 7.22** 的管理登录失败封禁脚本。使用 `target=script` 监听 WebFig、SSH、IP WinBox、API 等管理服务的标准认证失败日志，将达到阈值的来源 IPv4 加入 `BLOCK`，无需 Scheduler 定时扫描。

版本依据：[RouterOS 7.22 官方发布说明](https://forum.mikrotik.com/t/v7-22-stable-is-released/269092/1)引入了日志动作的 script 目标及日志规则的 comment 属性。最低版本依据功能引入时间确定，实际运行仍需按下方步骤验证。

默认策略：同一公网 IPv4 跨用户名、跨服务累计，从首次失败开始的固定 **5 分钟窗口内，第 4 次失败封禁 24 小时**，到期自动解封。私网及保留地址不计数，支持管理员白名单。

本文件添加的防火墙规则拦截访问路由器自身的全部 IPv4 流量，不依赖管理端口。若设备已有其他规则引用 `BLOCK`，新增封禁也会作用于那些规则。

**验证状态：已完成本地静态检查，尚未在 RouterOS 实机导入或验证真实登录链路。** IPv6、MAC WinBox 和非标准认证失败日志不在覆盖范围内；高频事件可能漏计，详见第三部分。

## 2. Quick Start：快速安装

先在运行 **RouterOS 7.22 或更高版本**的 CHR 或备用测试设备操作，并保留控制台或独立管理通道。

**第一步：确认版本，配置管理员白名单。**

```routeros
/system resource print
```

如果通过固定公网 IPv4 管理路由器，先执行以下命令。将 `YOUR_PUBLIC_IPV4` 替换为路由器日志中看到的管理员来源 IPv4；私网管理地址默认已忽略。

```routeros
/ip firewall address-list add list=LoginGuardAllow address=YOUR_PUBLIC_IPV4 comment="LoginGuard:trusted"
```

**第二步：选择一种安装方式。**

两种方式任选其一，不要连续执行或重复安装。

**当前不支持覆盖安装。** 已安装时先执行 [卸载脚本](routeros-login-guard-uninstall.rsc)，确认卸载完成，再安装新版；具体影响见第三部分的“覆盖安装与升级”。

### 方式 A：复制粘贴安装，无需上传文件

1. 打开 WinBox 的 **New Terminal**，或通过 SSH 进入 RouterOS 终端。如果上次粘贴后仍停在续行提示符，先按 `Ctrl+C` 回到普通命令提示符。
2. 打开 [routeros-login-guard.rsc](routeros-login-guard.rsc)，复制**文件的全部内容**，包括最外层的 `{` 和 `}`；不要只复制 `source={...}` 内部的事件处理代码。此方式无需上传文件。
3. 将完整内容一次性粘贴到终端，按 Enter 执行；等待终端返回命令提示符，再执行第三步的配置检查。

粘贴执行会直接创建配置，不是语法预览。若终端报错，先按“重复导入与安装报错”小节处理，避免反复粘贴。

安装脚本只含 ASCII 字符；中文解释放在正文中，避免终端处理中文粘贴时丢字、截断引号。不要把正文或 `[admin@CHR] >`、`{...` 等终端提示符一起复制进去。规则注释与诊断代码也使用 ASCII，便于稳定查找和清理。

### 方式 B：上传文件后安装

将 [routeros-login-guard.rsc](routeros-login-guard.rsc) 上传到 RouterOS 的 Files，然后在 Terminal 检查导入语法：

```routeros
/import file-name=routeros-login-guard.rsc verbose=yes dry-run=yes
```

`dry-run` 只检查导入语法，不验证真实认证日志、事件执行权限或防火墙效果。确认没有报错后安装：

```routeros
/import file-name=routeros-login-guard.rsc
```

**第三步：检查配置（两种安装方式通用）。**

```routeros
/system logging print detail where action="LoginGuardAction"
/ip firewall filter print detail
/log print where message~"LoginGuard:"
```

确认日志规则启用，`LoginGuard:input-drop` 规则位于现有 filter 规则之前。配置存在不代表封禁链路已验证，真实认证与拦截效果按第三部分的验收步骤检查。

## 3. 功能与细节

### 添加、查看和移除白名单

`LoginGuardAllow` 保存不参与失败计数的可信来源，只支持**单个 IPv4 精确匹配**，条目必须启用。不要填写 CIDR 网段、地址范围或域名；它不额外增加防火墙放行规则。

以下命令中的 `YOUR_PUBLIC_IPV4` 都代表路由器实际看到的管理员来源地址，不是路由器的 WAN 地址。

添加白名单：

```routeros
/ip firewall address-list add list=LoginGuardAllow address=YOUR_PUBLIC_IPV4 comment="LoginGuard:trusted"
```

查看白名单：

```routeros
/ip firewall address-list print detail where list="LoginGuardAllow"
```

移除白名单：

```routeros
/ip firewall address-list remove [find where list="LoginGuardAllow" and address=YOUR_PUBLIC_IPV4]
```

已经封禁的地址加入白名单后不会自动解封，还需执行下一节中的解封命令。经过代理或源 NAT 后，日志可能只看见共享出口地址，封禁会影响共用该地址的所有客户端。

### 手动解封 IP

将 `SOURCE_IPV4` 替换为需要解封的来源 IPv4，执行：

```routeros
/ip firewall address-list remove [find where list="BLOCK" and address=SOURCE_IPV4 and comment~"^LoginGuard:failures="]
/ip firewall address-list remove [find where list="LoginGuardCount" and address=SOURCE_IPV4]
```

第一条仅删除本脚本添加的封禁，第二条清除对应计数，避免立即再次达到阈值。`BLOCK` 中由其他来源创建的条目会保留，仍可能继续封禁该地址。

### 查看计数、封禁和运行状态

查看正在累计失败次数的来源，`comment` 是当前窗口已接收的失败日志条数，`timeout` 是窗口剩余时间：

```routeros
/ip firewall address-list print detail where list="LoginGuardCount"
```

查看完整封禁列表，其中可能包含其他规则或管理员添加的条目：

```routeros
/ip firewall address-list print detail where list="BLOCK"
```

查看封禁结果、处理错误和防火墙命中统计：

```routeros
/log print where message~"LoginGuard:"
/ip firewall filter print stats where comment="LoginGuard:input-drop"
```

检查脚本及日志动作：

```routeros
/system script print detail where name="LoginGuard"
/system logging action print detail where name="LoginGuardAction"
```

### 暂停与恢复

紧急停用时，通过仍可访问的可信管理通道，先停止新增计数，再停用本脚本的封禁规则：

```routeros
/system logging disable [find where action="LoginGuardAction"]
/ip firewall filter disable [find where comment="LoginGuard:input-drop"]
```

恢复时，先启用封禁规则，再启用日志规则：

```routeros
/ip firewall filter enable [find where comment="LoginGuard:input-drop"]
/system logging enable [find where action="LoginGuardAction"]
```

暂停不会删除已有计数或 `BLOCK` 条目，它们仍按原有超时到期；设备上其他引用 `BLOCK` 的规则也不会随之停用。

### 计数规则与参数调整

在 `/system script` 中编辑 `LoginGuard` 的源码，修改顶部三个参数：

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `failureWindow` | `5m` | 从首次失败开始计算的固定窗口时长 |
| `failureLimit` | `4` | 触发封禁所需的失败日志条数，必须为正整数 |
| `banTime` | `1d` | 本脚本新增封禁条目的有效时长 |

计数以来源 IPv4 为单位，跨用户名、跨服务累计。例如 SSH 2 次、WebFig 1 次、WinBox 1 次，在同一窗口内共 4 条失败日志即可达到默认阈值。

- 第 2、3 次失败只增加计数，不延长窗口；窗口过期后重新计数。
- 成功登录不会清零已有失败计数。
- 已启用的同地址封禁条目不会因后续失败而续期。
- 修改参数不会自动调整已有条目的到期时间，安装日志中的文字也只描述初始默认值。不要通过重复导入更新参数。
- 重启会清除动态计数和封禁条目；脚本、触发规则、防火墙规则及静态白名单保留。

这是固定窗口，并非任意连续 5 分钟的滑动窗口。RouterOS 会跳过脚本正在运行期间到达的匹配日志，不能保证高速攻击恰好第 4 次被封。计数条目刚好到期时，查询与更新之间也可能发生竞争，记录处理错误并漏掉一条事件，不能用作精确审计。

### 检测范围与防火墙行为

检测依据是带 `system,critical` topics 的标准管理认证失败日志，消息格式为：

```text
login failure for user <用户名> from <来源 IPv4> via <服务>
```

| 入口或事件 | 处理方式 |
| --- | --- |
| SSH、IP WinBox、WebFig、API | 官方明确举例的标准管理登录失败日志，统一匹配 |
| WebFig HTTP/HTTPS | 不按端口区分，是否计数取决于请求是否产生上述日志 |
| Telnet、FTP、API-SSL、REST 等 | 产生同样格式的日志时纳入，需要逐项实测，不能承诺每种失败都会记录 |
| 私网和保留 IPv4 地址 | 保守排除，不计数、不新增封禁；包含 CGNAT、回环、链路本地、文档、测试、组播等网段，完整列表见脚本 |
| IPv6、MAC WinBox、MAC Telnet | 不处理，不受本文件的 IPv4 规则保护 |
| PPP、VPN、HotSpot 等非标准认证日志 | 不处理 |
| TLS 握手失败、TCP 连接错误、HTTP 404 | 不等同于管理认证失败，不计数 |
| 成功登录后的异常行为、端口扫描 | 不检测 |

脚本提取最后一个 ` from ` 后的地址，避免把用户名里伪造的 `from` / `via` 内容当成实际来源；地址还需要通过 IPv4 转换和规范形式检查。

安装将 `BLOCK` 的 `input` 丢弃规则移动到现有 filter 规则之前，避免被 `established,related accept` 或管理服务放行规则绕过。它拦截被封禁来源访问路由器自身的**全部 IPv4 流量**，包括自定义管理端口、DNS、VPN，以及路由器发起连接的返回流量，不仅是 SSH/Web/WinBox。

本文件不修改 `forward` 链，也不新增访问权限，但会拦截 `BLOCK` 中已有的启用条目。如果其他防火墙规则也引用 `BLOCK`，脚本新增的地址同样会被那些规则匹配；最终封禁范围以设备全部规则为准。白名单只豁免本脚本的失败计数，不覆盖已有封禁规则。

### 配置对象与共享列表

| 对象名称 | 用途与归属 |
| --- | --- |
| `LoginGuard` | 处理登录失败日志的脚本 |
| `LoginGuardAction` | 将匹配日志交给脚本的日志动作 |
| `LoginGuardCount` | 脚本独占的动态计数地址列表；`address` 是来源 IPv4，`comment` 是失败日志条数，`timeout` 是固定窗口剩余时间 |
| `BLOCK` | 可共享的封禁地址列表；新增条目默认超时 24 小时，并以 `LoginGuard:failures=` 注释前缀标记归属，已有条目保留原配置 |
| `LoginGuardAllow` | 管理员维护的可信来源 IPv4 列表，只参与计数豁免 |

不要在 `LoginGuardCount` 中手工添加网段、域名或修改计数字段。请保留本脚本在 `BLOCK` 条目上的注释前缀，解封和卸载命令依靠它识别归属。

### 覆盖安装与升级

**当前安装脚本不支持覆盖安装，也不会自动更新已有脚本。** 它在创建配置前检查 `LoginGuard` 脚本、`LoginGuardAction` 日志动作、`LoginGuard:input-drop` 防火墙规则标记和 `LoginGuardCount` 计数列表；任一已存在时会报错停止。已有 `BLOCK` 条目和 `LoginGuardAllow` 白名单允许复用。

需要升级或重新安装时：

1. 记录当前自行修改过的窗口、阈值和封禁时长。
2. 执行下方卸载脚本，确认完成；出现报错时先处理，不能继续安装。
3. 按 Quick Start 重新安装，再恢复需要的参数。

卸载会清除本脚本的计数及封禁记录，重新安装使用文件中的默认参数；白名单和其他来源的 `BLOCK` 条目保留。卸载到安装完成之间，本方案暂不提供登录失败封禁，因此这不是原地更新或无中断升级。

### 重复导入与安装报错

同名脚本、日志动作、封禁规则或遗留计数条目存在时，安装会停止，不覆盖现有对象。已有 `BLOCK` 条目和白名单不会阻止安装。

安装不是事务，中途报错可能留下部分配置。先检查报错与已创建对象，再按卸载说明清理本方案对象后重新安装，不要反复导入。若同名对象不属于本方案，应先核实归属，不要直接删除。

如果粘贴记录中出现中文消失、右引号丢失，且提示符长期带着 `"`，说明输入的字符串没有闭合。之后的 `input does not match any value of script` / `action` 可能只是前面的脚本创建失败引起的连锁错误。末尾出现安装日志也不代表安装成功：外层块被解析错误打断后，后续粘贴的单独命令仍可能执行。

遇到这类问题，先按 `Ctrl+C` 取消未完成输入，再执行以下只读检查：

```routeros
/system script print detail where name="LoginGuard"
/system logging action print detail where name="LoginGuardAction"
/system logging print detail where action="LoginGuardAction"
/ip firewall filter print detail where comment~"^LoginGuard:"
/ip firewall address-list print detail where list="LoginGuardCount"
```

确认这些位置没有本方案的残留对象后，再复制当前版本的完整 ASCII 脚本重试。如果有残留，先核实其归属和是否启用，再做针对性处理；不要清空 `BLOCK`。旧版中文标记或粘贴截断产生的条目不会被下方的新版本卸载命令自动识别。

常见诊断代码：

| 代码 | 含义 |
| --- | --- |
| `LoginGuard:script-exists` | 同名脚本已存在，安装停止 |
| `LoginGuard:action-exists` | 同名日志动作已存在，安装停止 |
| `LoginGuard:rule-exists` | 本版本标记的防火墙规则已存在，安装停止 |
| `LoginGuard:counter-state-exists` | 存在遗留计数条目，安装停止 |
| `LoginGuard:invalid-counter` / `LoginGuard:nonpositive-counter` | 计数条目的 comment 无法转换为整数或不大于零 |
| `LoginGuard:handler-error` | 处理事件失败，后面的 error 保留原始错误 |
| `LoginGuard:blocked` | 已添加封禁，后续字段记录来源、服务、次数和时长 |
| `LoginGuard:uninstall-busy-retry` | 卸载已移除日志触发规则，但仍有运行中的处理任务；等待其结束后重新执行卸载 |

本地可执行 `node --test tests/paste-safety.test.mjs`，检查安装、卸载脚本和文档命令的 ASCII 字符约束。这不是 RouterOS 语法编译或实机认证测试。

### 测试设备验收

以下项目**尚未实机执行**。测试需要独立于管理员白名单的、由你控制的公网 IPv4 来源；`192.168.*` 私网或 `203.0.113.*` 文档地址按策略会被忽略，不能用来证明公网封禁成功。

1. 从 WebFig HTTP/HTTPS、SSH、IP WinBox 和实际启用的其他入口分别尝试错误认证，执行 `/log print where message~"login failure"`，记录服务名称、topics 和消息格式。没有标准日志的入口不算已覆盖。
2. 每次相隔数秒，从同一来源跨服务制造总共 4 条失败日志。以日志条数为准，客户端一次操作可能包含多次认证重试。第 1、2、3 条后计数应为 1、2、3，`timeout` 持续减少；第 4 条后出现 1 天封禁，计数条目移除。
3. 从被封禁来源确认所有已启用的 IPv4 管理服务无法访问，并看到封禁规则计数增长。通过另一管理通道确认路由器仍可管理；同时核对其他引用 `BLOCK` 的规则是否影响预期流量。
4. 解封后，仅发生 3 条失败日志并等待超过 5 分钟，再发生一次失败应重新计为 1；成功登录不清零已有失败计数。
5. 验证私网和启用的白名单地址不进入计数或封禁列表。可在受控客户端用包含 ` from ` / ` via ` 的用户名认证，确认提取的是实际来源，不能把用户名中的伪造地址封禁。
6. 仅在测试设备将 `banTime` 暂改为 `1m`，验证自动解封后恢复 `1d`。检查日志中没有权限不足、语法或条目访问错误。

### 卸载

独立文件：[routeros-login-guard-uninstall.rsc](routeros-login-guard-uninstall.rsc)。这是一次性卸载脚本，不需要先将它添加到 `/system script`。

卸载前确认目标名称和标记属于本项目。脚本先移除日志触发规则；若仍有 `LoginGuard` 任务运行，则以 `LoginGuard:uninstall-busy-retry` 停止，等待任务结束后重试，避免清理过程中被任务重新写入状态。

| 处理 | 范围 |
| --- | --- |
| 删除 | 使用 `LoginGuardAction` 的日志规则、该日志动作、`LoginGuard` 脚本 |
| 删除 | 同时匹配 `LoginGuard:input-drop` 注释、`input` 链、`drop` 动作和 `BLOCK` 来源列表的防火墙规则 |
| 删除 | `LoginGuardCount` 全部计数，以及 `BLOCK` 中注释以 `LoginGuard:failures=` 开头的封禁 |
| 保留 | `LoginGuardAllow` 白名单、`BLOCK` 中其他条目和其他防火墙规则 |

**方式 A：直接复制粘贴。** 打开 [routeros-login-guard-uninstall.rsc](routeros-login-guard-uninstall.rsc)，复制**文件的全部内容**（包括最外层的 `{` 和 `}`），粘贴到 RouterOS Terminal 后按 Enter 执行，无需上传文件。

**方式 B：上传文件。** 将卸载文件上传到 Files 后执行：

```routeros
/import file-name=routeros-login-guard-uninstall.rsc
```

卸载脚本按条件查找对象，已删除的对象不会再次匹配，可以再次执行以清理符合条件的剩余对象。旧版中文标记、粘贴截断产生的条目或手工改过标记的对象不会被自动识别，应先核对后单独处理，不能通过清空 `BLOCK` 代替卸载。

卸载完成后检查，以下查询不应再列出本方案的对应对象：

```routeros
/system script print detail where name="LoginGuard"
/system logging action print detail where name="LoginGuardAction"
/system logging print detail where action="LoginGuardAction"
/ip firewall filter print detail where comment="LoginGuard:input-drop" and chain=input and action=drop and src-address-list=BLOCK
/ip firewall address-list print detail where list="LoginGuardCount"
/ip firewall address-list print detail where list="BLOCK" and comment~"^LoginGuard:failures="
```

### 官方依据

- [RouterOS 7.22 发布说明：引入日志脚本动作及日志规则注释](https://forum.mikrotik.com/t/v7-22-stable-is-released/269092/1)
- [Log：日志触发脚本、标准登录失败消息和并发事件限制](https://manual.mikrotik.com/docs/diagnostics-monitoring-and-troubleshooting/log/)
- [2026-10-02 文档更新：日志章节示例在 RouterOS 7.25 上验证](https://manual.mikrotik.com/changelog/changelog-2026-10-02/)；7.25 是官方示例的测试版本，不是本项目的最低版本，也不代表本脚本已经实机验证。
- [Scripting：字符串查找、类型转换、返回和异常处理](https://manual.mikrotik.com/docs/developer-guides/scripting/)
- [Address lists：动态条目的超时与重启行为](https://manual.mikrotik.com/docs/firewall-and-quality-of-service/firewall/address-lists/)
- [REST API：HTTP/HTTPS 服务归属](https://manual.mikrotik.com/docs/developer-guides/rest-api/)
- [Script job：检查仍在运行的脚本任务](https://manual.mikrotik.com/docs/cli-reference/system/script/job/)

### License

本项目采用 **GNU General Public License v3.0**（SPDX：`GPL-3.0-only`），完整许可证见 [LICENSE](LICENSE)。
