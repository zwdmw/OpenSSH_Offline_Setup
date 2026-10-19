Windows OpenSSH 离线安装包
==========================

适用系统：64 位 Windows 10/11
默认账号：运行脚本的当前 Windows 用户

使用方法：

1. 将整个 OpenSSH_Offline_Setup 文件夹复制到目标 Windows 电脑。
2. 保持 BAT 和 MSI 文件位于同一文件夹，不要单独移动其中一个文件。
3. 双击 setup_openssh_server.bat，并在 UAC 窗口中允许管理员权限。
   如需指定其他本地账号，可在命令提示符中执行：
   setup_openssh_server.bat username
4. 脚本会先检查系统自带 OpenSSH；无法联网时自动使用同目录的 MSI 安装。
5. 脚本会启动 sshd、设置开机启动、开放 TCP 22，并执行本机连接测试。
6. 无论成功或失败，都会在 BAT 同目录生成 OpenSSH_Setup_计算机名_时间.txt 日志。

安装成功后，在 Linux 电脑执行：

ssh username@WINDOWS_IP

如果提示密码认证失败，请在目标 Windows 的管理员命令提示符中设置非空密码：

net user username *

安全校验：

OpenSSH-Win64-v10.0.0.0.msi
SHA-256: ddec9c53864280759cf9f74791cefd387100e3946aa849a1c138a4ed1b96b7d9

安装包来自 Microsoft PowerShell/Win32-OpenSSH 官方 GitHub Release 10.0.0.0p2-Preview。

注意：诊断日志可能包含计算机名、账号、域、IP 地址、网络配置和事件日志。
公开分享日志前请先脱敏。
