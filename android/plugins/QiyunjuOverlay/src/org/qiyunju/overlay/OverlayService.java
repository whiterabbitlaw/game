package org.qiyunju.overlay;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.IBinder;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.TextView;

/**
 * 最小悬浮气泡：点击把主 Activity 拉到前台。真正的畅聊 UI 仍在游戏内（网页版请用 PWA / 画中画）。
 */
public class OverlayService extends Service {
    public static final String CHANNEL_ID = "qiyunju_overlay";
    private WindowManager windowManager;
    private View bubble;
    private WindowManager.LayoutParams params;
    private float lastX;
    private float lastY;
    private int startX;
    private int startY;

    @Override
    public void onCreate() {
        super.onCreate();
        ensureChannel();
        Notification.Builder nb;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nb = new Notification.Builder(this, CHANNEL_ID);
        } else {
            nb = new Notification.Builder(this);
        }
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent pi = PendingIntent.getActivity(
                this, 0, launch == null ? new Intent() : launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification n = nb.setContentTitle("栖云居")
                .setContentText("畅聊悬浮窗运行中")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(pi)
                .build();
        startForeground(17, n);

        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        TextView tv = new TextView(this);
        tv.setText("栖");
        tv.setTextSize(18);
        tv.setPadding(28, 20, 28, 20)
        ;
        tv.setBackgroundColor(0xE63D3358);
        tv.setTextColor(0xFFFFFFFF);
        bubble = tv;

        int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;
        params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT);
        params.gravity = Gravity.TOP | Gravity.START;
        params.x = 24;
        params.y = 240;
        tv.setOnTouchListener((v, ev) -> {
            switch (ev.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    lastX = ev.getRawX();
                    lastY = ev.getRawY();
                    startX = params.x;
                    startY = params.y;
                    return true;
                case MotionEvent.ACTION_MOVE:
                    params.x = startX + (int) (ev.getRawX() - lastX);
                    params.y = startY + (int) (ev.getRawY() - lastY);
                    windowManager.updateViewLayout(bubble, params);
                    return true;
                case MotionEvent.ACTION_UP:
                    if (Math.abs(ev.getRawX() - lastX) < 12 && Math.abs(ev.getRawY() - lastY) < 12) {
                        Intent i = getPackageManager().getLaunchIntentForPackage(getPackageName());
                        if (i != null) {
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
                            startActivity(i);
                        }
                    }
                    return true;
                default:
                    return false;
            }
        });
        windowManager.addView(bubble, params);
    }

    private void ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID, "栖云居悬浮窗", NotificationManager.IMPORTANCE_LOW);
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) {
                nm.createNotificationChannel(ch);
            }
        }
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        if (windowManager != null && bubble != null) {
            windowManager.removeView(bubble);
        }
        super.onDestroy();
    }
}
