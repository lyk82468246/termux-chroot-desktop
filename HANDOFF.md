# HANDOFF

给接手的 Agent / 开发者的入口。

**先读：[docs/14-handoff.md](docs/14-handoff.md)**（环境、里程碑、坑、未解决问题、协作规则）。

## 当前状态（2025-11）

| 能力 | 状态 |
|---|---|
| XFCE 桌面（Termux:X11 + chroot） | 可用 |
| ARM64 Windows 程序 | 可用（原生 Hangover） |
| AMD64 Windows 程序 | 可用（FEX） |
| I386 Windows 程序 | 可用（WowBox64 默认，FEX 可覆盖） |
| D3D9 / D3D10 / D3D11（WineD3D） | 可用（x64 + x86，GPU OpenGL FD610） |
| DXVK | **不可用**：Adreno 610 + Turnip 缺 multiViewport |
| Wine 控件中文显示 | 方框（数据正确，字体回退问题，未修） |
| Office Tool Plus GUI | **未解决**：CoreCLR failfast，见 docs/14 §9 |

## 三条命令先跑通

```bash
bash ~/bin/termux-gui-start.sh          # 桌面
bash ~/bin/termux-gui-attach.sh         # 进容器
win-run /tmp/win-tests/ia32/hello.exe 5 # 期望 rc=5，日志含 [BOX64]
```

## 不要做

- 未获用户批准就改正式脚本 / Prefix / 注册表 / 系统包；
- 把 `FD_DEV_FEATURES` 写进启动脚本（DXVK 会画错，见 docs/spikes/）；
- 把 EXE 放在 bind 挂载目录（`/media/sd`、`/tmp/termux-win-run`）里执行；
- 用 Linux 原生 dotnet-dump 抓 Wine 里 .NET 进程（Wine 管道限制，见 docs/14 §8.5）。
