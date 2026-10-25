# AutoDL 算力监控

非官方 AutoDL 库存监控工具。macOS 为主版本；Windows 为次要版本，**尚未经过 Windows 实机测试**。

## 下载

[前往 Releases](https://github.com/RY150150/autodl-gpu-monitor/releases/latest)

| 版本 | 文件 | 状态 |
| --- | --- | --- |
| macOS 主版本 | AutoDLMonitor-macOS-AppleSilicon.zip | Apple Silicon；已在开发机检查界面和只读监控 |
| Windows 次要版本 | AutoDLMonitor-Windows-secondary-UNTESTED.zip | 实验性；没有 Windows 实机、登录或下单验证 |

构建成功不代表功能已经通过端到端验证。未提供 Intel Mac 安装包。

## 使用

1. 安装 Google Chrome，解压下载文件。Mac 打开 AutoDLMonitor.app；Windows 打开完整文件夹内的 AutoDLMonitor-Windows.exe，不要只移动 exe。
2. 选择地区、GPU 型号、卡数、计费方式和镜像类型，**自行填写自己账号内可用镜像的准确名称**。发布版不预设任何镜像名称。
3. 核对价格上限和自动租赁开关后点击「开始监控」。首次使用需在应用的专用 Chrome 窗口登录自己的 AutoDL 账号。
4. 如果只看库存、不希望付费下单，先取消「自动租赁」。

下载包已包含 Python 和 Playwright，使用者无需安装这些依赖。仍需要 Chrome、有效的 AutoDL 登录状态、可用镜像和足够余额。不要同时运行多个监控进程。

默认配置为按量计费、内蒙B区、RTX 4090、1卡、价格上限 3 元/小时。目标轮询周期为 5 秒；页面加载或网络延迟时可能更慢。电脑休眠、退出应用或关闭浏览器会中断监控。下拉选项是创建页的配置快照，**不保证每个地区和 GPU 型号的任意组合都存在**；页面结构和镜像选择方式变化可能使自动化失效。

## 费用与风险

- 自动租赁默认开启。启用后发现符合筛选和价格上限的资源会尝试提交一个订单，可能产生实际费用。
- 每次监控最多尝试提交一个订单；结果不明确时停止，不自动再次下单。重新点击开始属于新的监控任务。
- 价格上限按所选计费周期校验，不是累计费用或租赁时长上限；停止监控和退出应用不会关闭或取消已经创建的云实例。
- 不绕过登录、验证码、风控或平台规则。出现核验问题需要人工检查。
- 界面和本地模拟测试不代表实际付费下单已验证。使用前请先关闭自动租赁进行只读检查。

## 租用日志

窗口内可切换运行日志和租用日志。仅在实例列表中确认新增且匹配的实例后才显示「租用成功」；仅点击按钮会显示「订单已提交」，无法核验时显示「结果待确认」。

记录包含时间、所选配置、页面报价和确认到的实例 ID，不保存密码、Cookie 或 SSH 凭据。镜像信息是用户所选配置，页面价格不是最终结算账单。实例列表分页或读取不完整时会保守标记待确认；已有实例不会被补记为新租用成功。

- macOS：~/Library/Application Support/AutoDLMonitor/rental-history.jsonl
- Windows：%LOCALAPPDATA%/AutoDLMonitor/rental-history.jsonl

Chrome 登录配置也保存在相应用户数据目录中，不在程序包内，不会上传到 GitHub。

## 从源码构建

构建需要 Python 3.12 及 requirements-build.txt 中的依赖；macOS 还需要 Swift/Apple Command Line Tools。

macOS：

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-build.txt
PYTHON="$PWD/.venv/bin/python" bash scripts/build-macos.sh
```

Windows（次要版、未实机测试）：

```powershell
py -3.12 -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements-build.txt
.\scripts\build-windows.ps1 -Python .\.venv\Scripts\python.exe
```

构建结果写入 dist/。GitHub Actions 的 Windows secondary build 工作流可手动触发，仅完成构建和离线单元测试，不会登录 AutoDL 或下单。安装包未进行 Apple 公证或 Windows 商业代码签名；请核对下载来源和 SHA-256，不要为运行它而关闭系统安全防护。
