# 栖云居 Android 导出与悬浮窗

本目录是 **脚手架**，不是可安装的 APK。当前构建环境没有 JDK、没有 Android SDK（`ANDROID_HOME` 未设置），也没有签名用的 keystore，因此 **无法在这里编译或打包**。不要把 APK 发布到任何应用商店。

网页版已经支持：把站点「添加到主屏幕」（PWA）、手机上的紧凑气泡小窗，以及桌面 Chrome 的文档画中画。多数情况下用网页即可实时语音和畅聊。原生悬浮窗只在需要「安卓系统级 overlays、游戏不在前台也能看到气泡」时才有必要。

## 现成与缺失

| 项 | 状态 |
| --- | --- |
| Godot 4.7.2 Android 导出模板 | 本机构建机若已安装，一般在 `~/.local/share/godot/export_templates/4.7.2.stable/`（`android_source.zip`、`android_debug.apk`、`android_release.apk`） |
| 工程内 Android 导出预设 | `export_presets.cfg` 中的 **Android**，包名 `org.qiyunju.game`，已声明 `INTERNET`、`RECORD_AUDIO`、`SYSTEM_ALERT_WINDOW` |
| 悬浮窗插件源码 | `android/plugins/QiyunjuOverlay/`（申请权限 + 可拖动气泡，点击拉起主界面） |
| 编好的 AAR | **没有**。需要先在本机编出 `QiyunjuOverlay.release.aar` 再放到插件目录 |
| JDK 17 | **缺失**（本环境 `java` 不存在） |
| Android SDK / NDK / `ANDROID_HOME` | **缺失** |
| debug / release keystore | **缺失**（不要把密码或 keystore 提交进仓库） |

## 在有工具链的机器上构建

1. 安装 **JDK 17**、**Android SDK 34**、对应 NDK，并设置 `ANDROID_HOME`（以及 `JAVA_HOME`）。
2. 在 Godot 编辑器 **编辑器设置 → 导出 → Android** 里填 SDK 路径；生成仅保存在本机的 debug keystore（`keytool -genkey -v -keystore debug.keystore -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000`），路径不要提交。
3. 把 Godot 4.7.2 的 `godot-lib`（导出模板或官方 AAR）放到 `android/plugins/QiyunjuOverlay/libs/`，然后：

   ```bash
   cd android/plugins/QiyunjuOverlay
   gradle assembleRelease
   # 将生成的 AAR 复制为 QiyunjuOverlay.release.aar，与 plugin.cfg 中 binary 一致
   ```

4. 在 Godot 里启用该 Android 插件，导出 Android（Gradle Build）。首次会向用户申请「显示在其他应用上层」和麦克风权限。
5. 游戏内可在需要时调用（插件启用后）：

   ```gdscript
   if Engine.has_singleton("QiyunjuOverlay"):
       var ov = Engine.get_singleton("QiyunjuOverlay")
       if not ov.canDrawOverlays():
           ov.requestOverlayPermission()
       else:
           ov.startOverlay()
   ```

   目前客户端尚未自动调用这些方法：请在本机打出 APK 并确认权限流程后再接 UI 按钮。

6. **不要**把签名文件、密码或商店密钥提交到公开仓库；**不要**上架应用商店（本任务只要求可构建的脚手架）。

## 权限说明

`SYSTEM_ALERT_WINDOW` 是敏感权限，用户必须在系统设置里手动允许。悬浮窗只用于拉回游戏，实时语音仍建议在应用前台或网页 PWA 里进行（后台录音受限且体验差）。
