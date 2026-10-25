# Windows 次要版本：尚未经过实机测试

这是 macOS 主版本之外的实验性、次要版本，不应视为同等成熟的正式 Windows 产品。

- 没有经过 Windows 桌面的实际界面操作、Chrome 登录、库存监控或付费下单验证。
- CI 构建和离线单元测试通过，只代表能够构建及部分逻辑通过测试。
- 下载包含 Python、Tkinter、Playwright 和监控程序，不需要另装 Python；仍需要安装 Google Chrome。
- 解压完整目录后运行 AutoDLMonitor-Windows.exe。保留同目录下的 autodl_watch.exe 和 _internal 文件夹。
- 不预设镜像名称，必须填写自己账号可用的镜像。
- 使用前先关闭自动租赁，仅进行只读监控检查。自动租赁可能产生费用；停止程序不会取消已提交的云实例。
- 程序未进行 Windows 商业代码签名。请核验来源与 SHA-256，不要关闭系统安全保护。

反馈问题时请注明 Windows 版本及错误信息，先去除账号、Cookie、密码、SSH 信息和个人租用记录。
