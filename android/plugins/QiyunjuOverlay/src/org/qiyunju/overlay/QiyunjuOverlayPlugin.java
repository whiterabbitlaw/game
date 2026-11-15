package org.qiyunju.overlay;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/**
 * 栖云居悬浮窗插件：申请 SYSTEM_ALERT_WINDOW，并启动 OverlayService。
 * 需要在有 JDK + Android SDK 的机器上编成 AAR 后再打进 APK。本仓库只提供源码脚手架。
 */
public class QiyunjuOverlayPlugin extends GodotPlugin {
    public QiyunjuOverlayPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "QiyunjuOverlay";
    }

    @UsedByGodot
    public boolean canDrawOverlays() {
        Activity a = getActivity();
        if (a == null) {
            return false;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return Settings.canDrawOverlays(a);
        }
        return true;
    }

    @UsedByGodot
    public void requestOverlayPermission() {
        Activity a = getActivity();
        if (a == null) {
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(a)) {
            Intent i = new Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + a.getPackageName()));
            a.startActivity(i);
        }
    }

    @UsedByGodot
    public boolean startOverlay() {
        Activity a = getActivity();
        if (a == null) {
            return false;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(a)) {
            requestOverlayPermission();
            return false;
        }
        Intent i = new Intent(a, OverlayService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            a.startForegroundService(i);
        } else {
            a.startService(i);
        }
        return true;
    }

    @UsedByGodot
    public void stopOverlay() {
        Activity a = getActivity();
        if (a == null) {
            return;
        }
        a.stopService(new Intent(a, OverlayService.class));
    }
}
