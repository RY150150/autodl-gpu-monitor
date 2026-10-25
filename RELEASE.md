# v1.0.0

## macOS 主版本

- Apple Silicon Mac，原生 AppKit 界面。
- 不预设镜像名称，使用者必须填写自己账号内可用的镜像。
- 内置 Python/Playwright；仍需安装 Chrome 并登录 AutoDL。
- 保留 5 秒目标轮询、配置选择、价格上限、每次任务最多提交一台及本地租用日志。
- 已在开发机检查界面、镜像为空时的启动阻止和离线逻辑；未进行真实付费下单测试。

## Windows 次要版本：尚未经过 Windows 实机测试

**Windows 版是实验性、次要版本，没有经过 Windows 桌面、Chrome 登录、库存监控或付费下单验证。**
CI 构建和离线测试通过不能替代实际使用验证。文件名中保留 secondary-UNTESTED 标注。请解压完整目录，保留内部运行依赖。

## 注意

- 自动租赁可能产生实际费用，默认开启。首次使用请关闭自动租赁，仅做只读检查。
- 停止程序不会关闭或取消云端已提交的实例。
- 查看 README 和 WINDOWS-UNTESTED.md；请核对 SHA-256。安装包未经 Apple 公证或 Windows 商业代码签名。
- 不包含任何登录配置、密码、Cookie 或个人租用记录。
