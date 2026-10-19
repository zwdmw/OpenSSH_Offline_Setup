# Windows OpenSSH 离线安装工具

用于在无法正常联网安装 Windows 可选功能的环境中，安装、启动并诊断 Windows OpenSSH Server。

仓库内附带微软 `PowerShell/Win32-OpenSSH` 发布的 64 位 MSI，因此下载整个仓库后即可离线使用。

## 功能

- 检测系统内置的 OpenSSH Server 可选功能
- 优先使用同目录的离线 MSI 安装包
- 启动 `sshd` 并设为自动启动
- 创建或启用 TCP 22 入站防火墙规则
- 校验 `sshd` 配置、监听端口和本机连接
- 生成包含系统、服务、网络和 OpenSSH 状态的诊断日志

## 系统要求

- 64 位 Windows 10 或 Windows 11
- 管理员权限
- PowerShell 5.1 或更高版本

## 使用方法

1. 下载仓库 ZIP，或复制整个项目目录到目标 Windows 电脑。
2. 保持 `setup_openssh_server.bat` 和 `OpenSSH-Win64-v10.0.0.0.msi` 位于同一目录。
3. 双击 `setup_openssh_server.bat`，在 UAC 窗口中允许管理员权限。
4. 默认使用当前 Windows 用户作为 SSH 登录账号。

也可以从命令提示符指定其他本地账号：

```bat
setup_openssh_server.bat username
```

安装成功后，从另一台电脑连接：

```bash
ssh username@WINDOWS_IP
```

如果密码认证失败，请在目标 Windows 的管理员命令提示符中为该账号设置非空密码：

```bat
net user username *
```

## 安全校验

在 Windows 中校验 MSI：

```bat
certutil -hashfile OpenSSH-Win64-v10.0.0.0.msi SHA256
```

预期 SHA-256：

```text
ddec9c53864280759cf9f74791cefd387100e3946aa849a1c138a4ed1b96b7d9
```

完整校验值见 `SHA256SUMS.txt`。

## 安全提示

- 脚本会启用 `sshd`，并为所有 Windows 防火墙配置文件开放 TCP 22。
- 请为登录账号使用强密码，或在安装后配置 SSH 公钥认证。
- 诊断日志可能包含计算机名、账号、域、IP 地址、网络配置、事件日志和 `sshd_config`。公开分享日志前请先脱敏。
- 仓库附带的是上游 `10.0.0.0p2-Preview` 发布资产。生产环境使用前请自行评估版本与组织安全策略。

## 安装包来源

- 上游项目：`PowerShell/Win32-OpenSSH`
- 上游发布：`10.0.0.0p2-Preview`
- 文件：`OpenSSH-Win64-v10.0.0.0.msi`
- 本仓库中的 MSI 保持上游原始内容，SHA-256 与上游发布资产一致

## 许可证

本仓库原创脚本与文档使用 MIT License，见 `LICENSE`。

附带的 OpenSSH MSI 是第三方软件，不适用本仓库的 MIT License；其版权和许可由 OpenSSH 及微软上游项目规定，见 `THIRD_PARTY_NOTICES.md`。
