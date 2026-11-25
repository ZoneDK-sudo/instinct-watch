import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// "Ride Ready": big time, a step-goal ring around the edge, heart rate in the
// Instinct's round subscreen, and a strip of today's heart-rate history.
// Zone limits match the watch's own settings (max HR 193).
class RideReadyView extends WatchUi.WatchFace {
    private const ZONES = [97, 116, 135, 154, 174];

    function initialize() {
        WatchFace.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        var info = ActivityMonitor.getInfo();
        var steps = info.steps != null ? info.steps : 0;
        var goal = (info.stepGoal != null && info.stepGoal > 0) ? info.stepGoal : 5000;

        // Step-goal ring: a thick arc that fills clockwise from 12 o'clock.
        var frac = steps.toFloat() / goal;
        if (frac > 1.0) { frac = 1.0; }
        dc.setPenWidth(6);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(w / 2, h / 2, w / 2 - 4);
        if (frac > 0.0) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            var end = 90 - (frac * 360).toNumber();
            dc.drawArc(w / 2, h / 2, w / 2 - 4, Graphics.ARC_CLOCKWISE, 90, end);
        }
        dc.setPenWidth(1);

        // Time and date
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var timeStr = hour.format("%d") + ":" + clock.min.format("%02d");
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2 - 8, h * 0.30, Graphics.FONT_NUMBER_HOT, timeStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var now = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        dc.drawText(w / 2 - 8, h * 0.52, Graphics.FONT_XTINY,
            (now.day_of_week as String).toUpper() + " " + now.day.format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Steps line
        dc.drawText(w / 2, h * 0.63, Graphics.FONT_XTINY, steps.format("%d") + " / " + goal.format("%d") + " STEPS",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        drawHrHistory(dc, w, h);
        drawSubscreen(dc);
    }

    // Heart rate (with zone number) inside the Instinct's round subscreen.
    private function drawSubscreen(dc as Graphics.Dc) as Void {
        var hr = currentHeartRate();
        var label = hr != null ? hr.format("%d") : "--";
        if (WatchUi has :getSubscreen) {
            var box = WatchUi.getSubscreen();
            if (box != null) {
                var cx = box.x + box.width / 2;
                var cy = box.y + box.height / 2;
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx, cy, box.width / 2);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, cy - 6, Graphics.FONT_SMALL, label, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                dc.drawText(cx, cy + 13, Graphics.FONT_XTINY, hr != null ? "Z" + zoneOf(hr).format("%d") : "HR",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                return;
            }
        }
        // Devices without a subscreen: show it under the steps instead.
        dc.drawText(dc.getWidth() / 2, dc.getHeight() * 0.92, Graphics.FONT_XTINY, label + " BPM",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Last ~4 hours of heart rate as a small bar strip along the bottom.
    private function drawHrHistory(dc as Graphics.Dc, w as Number, h as Number) as Void {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getHeartRateHistory)) { return; }
        var iter = SensorHistory.getHeartRateHistory({ :period => new Time.Duration(4 * 3600), :order => SensorHistory.ORDER_NEWEST_FIRST });
        if (iter == null) { return; }
        var left = (w * 0.22).toNumber();
        var right = (w * 0.78).toNumber();
        var base = (h * 0.84).toNumber();
        var tall = (h * 0.12).toNumber();
        var lo = iter.getMin();
        var hi = iter.getMax();
        if (lo == null || hi == null || hi <= lo) { return; }
        var x = right;
        var sample = iter.next();
        var every = 0;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        while (sample != null && x >= left) {
            // one bar per ~3 samples keeps the strip readable on a 176 px screen
            if (every % 3 == 0 && sample.data != null) {
                var bh = ((sample.data - lo).toFloat() / (hi - lo) * tall).toNumber() + 1;
                dc.drawLine(x, base, x, base - bh);
                x -= 2;
            }
            every += 1;
            sample = iter.next();
        }
    }

    private function currentHeartRate() as Number? {
        var act = Activity.getActivityInfo();
        if (act != null && act.currentHeartRate != null) { return act.currentHeartRate; }
        if (ActivityMonitor has :getHeartRateHistory) {
            var s = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (s != null && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) { return s.heartRate; }
        }
        return null;
    }

    private function zoneOf(hr as Number) as Number {
        for (var i = 0; i < ZONES.size(); i++) {
            if (hr <= ZONES[i]) { return i + 1; }
        }
        return 5;
    }

    function onEnterSleep() as Void { WatchUi.requestUpdate(); }
    function onExitSleep() as Void { WatchUi.requestUpdate(); }
}
