# 10 · 桌面声音（PulseAudio → Android）

## 为什么默认没声音

容器里没有音频服务，而直接走 ALSA 也不行：

```
$ speaker-test -D default
Playback open error: -112,Host is down
```

`aplay -l` 能看到 `bengal-idp-snd-card`，但 DSP 被 Android 的 audio HAL 占着，
容器拿不到 PCM。所以必须把声音**送回 Android 的音频服务**。

## 方案

```
容器应用 → libpulse → TCP 127.0.0.1:4713 → Termux PulseAudio
                                              → module-sles-sink (OpenSL ES)
                                                → Android AudioFlinger → 扬声器
```

Termux 的 `pulseaudio` 自带 `module-sles-sink` 和 `module-aaudio-sink`，
这是唯一能绕过 ALSA 限制的路径。

## 启动脚本做了什么

`termux-gui-start.sh` 在拉起桌面之前：

```bash
pulseaudio --start --exit-idle-time=-1
pactl load-module module-native-protocol-tcp port=4713 listen=127.0.0.1 auth-anonymous=1
```

然后把 `PULSE_SERVER=tcp:127.0.0.1:4713` 写进会话环境（`env -i` 需要显式传）。
`attach` 里也会做同样的准备，所以从终端启动的 GUI 程序一样有声。

## 开关

```bash
AUDIO=0 bash ~/bin/termux-gui-start.sh     # 这次不要声音
PULSE_PORT=4714 bash ~/bin/termux-gui-start.sh
```

## 验证

容器内（`attach` 进去即可，环境已带好）：

```bash
pactl info                    # Server String: tcp:127.0.0.1:4713
pactl list short sinks        # OpenSL_ES_sink ... RUNNING
pactl load-module module-sine frequency=880   # 应该能听到 880Hz
pactl unload-module <id>
```

用客户端库验证（不是只看服务端）：

```bash
head -c 192000 /dev/zero | pacat --format=s16le --rate=48000 --channels=2 --playback
```

## 注意

1. **音量走 Android 媒体音量**，不是容器内音量。桌面音量图标可能不起作用，
   直接调平板的媒体音量即可。
2. sink 固定 44.1kHz/2ch，48kHz 的流会被 PulseAudio 重采样。
3. PulseAudio 以 Termux 用户运行，**停止桌面不会杀掉它**（它是独立的声音服务）。
   要彻底停：`pulseaudio -k`。
4. 首次启动 PA 需要 `HOME` 和 `XDG_RUNTIME_DIR` 正确。用 `su 10234 -c` 手动测试时
   必须显式传，否则会报 `Home directory not accessible: Unknown error 13`。
5. 早前 `module-native-protocol-tcp` 会打印 `Failure: Module initialization failed`，
   但模块其实已经加载成功——判断依据应该是 `pactl list short modules` 里有没有它。
