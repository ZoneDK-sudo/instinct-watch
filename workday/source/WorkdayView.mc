import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Workday: a desk-day watch face for the Instinct 2X (176 x 176, 1-bit).
//
//   +-------------------------+
//   |   WED 25         ( 64 ) |   top-left block, right-aligned beside the
//   |  [bat]5d [msg]2  ( BODY)|   Body Battery subscreen
//   |   STRESS 35             |
//   | 3h24 LEFT               |
//   |        12:59            |   big bold clock, full width
//   | [][][][][]. . .    5/8  |   hours moved during work hours
//   |   SITTING 14m  5PM ~31  |   inverts to a black MOVE bar after the sitting limit
//   +-------------------------+
//
// Work hours, the hourly step goal, the sitting limit and weekend tracking are
// settings you change in the Garmin Connect app (resources/settings).
class WorkdayView extends WatchUi.WatchFace {
    private const MAX_HOURS = 12;
    private const MOVE_STEPS = 30;   // steps in one minute that count as getting up

    // Layout (pixels on the 176 x 176 screen)
    private const INFO_RIGHT = 97;   // right edge of the top-left block
    private const INFO_ROWS = [13, 27, 41, 55];
    private const TIME_Y = 98;
    private const HOURS_Y = 134;
    private const BOTTOM_Y = 153;

    // Settings
    private var _start as Number = 9;
    private var _end as Number = 17;
    private var _hourGoal as Number = 250;
    private var _sitWarn as Number = 50;
    private var _weekends as Boolean = false;

    // Tracking state (saved to storage)
    private var _day as Number = 0;
    private var _hourSteps as Array<Number> = new Array<Number>[12];
    private var _trackedStart as Number = -1;
    private var _lastHour as Number = -1;
    private var _stepsAtHourStart as Number = 0;
    private var _prevSteps as Number = -1;
    private var _lastMove as Number = 0;

    private var _timeFont as Graphics.FontType = Graphics.FONT_NUMBER_HOT;

    function initialize() {
        WatchFace.initialize();
        clearHours();
        load();
        loadSettings();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        // Bold condensed DIN-style digits rendered from Bahnschrift (see tools/make-font.ps1)
        _timeFont = WatchUi.loadResource(Rez.Fonts.TimeFont) as Graphics.FontType;
    }

    function loadSettings() as Void {
        _start = readNumber("StartHour", 9, 0, 23);
        _end = readNumber("EndHour", 17, 1, 24);
        if (_end <= _start) { _end = _start + 8; }
        if (_end - _start > MAX_HOURS) { _end = _start + MAX_HOURS; }
        if (_end > 24) { _end = 24; }
        _hourGoal = readNumber("HourGoal", 250, 50, 2000);
        _sitWarn = readNumber("SitWarnMinutes", 50, 15, 180);
        var wk = Application.Properties.getValue("WorkWeekends");
        _weekends = (wk instanceof Boolean) ? wk : false;
        // The hour boxes are indexed from the start hour, so a new start hour starts them fresh.
        if (_start != _trackedStart) {
            clearHours();
            _trackedStart = _start;
            save();
        }
    }

    private function readNumber(key as String, dflt as Number, lo as Number, hi as Number) as Number {
        var v = Application.Properties.getValue(key);
        var n = (v instanceof Number) ? v : dflt;
        if (n < lo) { n = lo; }
        if (n > hi) { n = hi; }
        return n;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var nowSec = Time.now().value();
        var clock = System.getClockTime();
        var info = ActivityMonitor.getInfo();
        var steps = info.steps != null ? info.steps as Number : 0;
        track(nowSec, clock, steps);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);

        var dow = Gregorian.info(Time.now(), Time.FORMAT_SHORT).day_of_week as Number; // 1 = Sunday
        var workday = _weekends || (dow != 1 && dow != 7);
        var minsNow = clock.hour * 60 + clock.min;
        var inDay = workday && minsNow >= _start * 60 && minsNow < _end * 60;

        drawInfoBlock(dc, minsNow, workday, inDay);
        drawSubscreen(dc);

        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        dc.drawText(w / 2, TIME_Y, _timeFont, hour.format("%d") + ":" + clock.min.format("%02d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (workday) {
            drawHours(dc, w, clock.hour);
        } else {
            dc.drawText(w / 2, HOURS_Y, Graphics.FONT_XTINY, formatThousands(steps) + " STEPS TODAY",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        drawBottom(dc, w, nowSec, minsNow, inDay);
    }

    // ---- tracking ---------------------------------------------------------

    private function clearHours() as Void {
        _hourSteps = new Array<Number>[MAX_HOURS];
        for (var i = 0; i < MAX_HOURS; i++) { _hourSteps[i] = 0; }
    }

    private function track(nowSec as Number, clock as System.ClockTime, steps as Number) as Void {
        var g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var day = (g.year as Number) * 10000 + (g.month as Number) * 100 + (g.day as Number);
        var dirty = false;
        if (day != _day) {
            _day = day;
            clearHours();
            _lastHour = -1;
            _prevSteps = steps;
            _lastMove = nowSec;
            dirty = true;
        }
        if (clock.hour != _lastHour) {
            _lastHour = clock.hour;
            _stepsAtHourStart = steps;
            dirty = true;
        }
        var idx = clock.hour - _start;
        if (idx >= 0 && idx < MAX_HOURS && clock.hour < _end) {
            var inHour = steps - _stepsAtHourStart;
            if (inHour > _hourSteps[idx]) { _hourSteps[idx] = inHour; }
        }
        if (_prevSteps < 0 || steps < _prevSteps) { _prevSteps = steps; }
        if (steps - _prevSteps >= MOVE_STEPS) {
            _lastMove = nowSec;
            dirty = true;
        }
        _prevSteps = steps;
        if (_lastMove == 0) { _lastMove = nowSec; }
        if (dirty) { save(); }
    }

    private function load() as Void {
        var s = Application.Storage.getValue("wd");
        if (s instanceof Dictionary) {
            var day = s["day"];
            if (day instanceof Number) { _day = day; }
            var hs = s["hours"];
            if (hs instanceof Array && hs.size() == MAX_HOURS) { _hourSteps = hs as Array<Number>; }
            var st = s["start"];
            if (st instanceof Number) { _trackedStart = st; }
            var lh = s["lastHour"];
            if (lh instanceof Number) { _lastHour = lh; }
            var sh = s["hourStart"];
            if (sh instanceof Number) { _stepsAtHourStart = sh; }
            var lm = s["lastMove"];
            if (lm instanceof Number) { _lastMove = lm; }
        }
    }

    private function save() as Void {
        Application.Storage.setValue("wd", {
            "day" => _day, "hours" => _hourSteps, "start" => _trackedStart, "lastHour" => _lastHour,
            "hourStart" => _stepsAtHourStart, "lastMove" => _lastMove
        });
    }

    // ---- drawing ----------------------------------------------------------

    // Four short rows beside the subscreen: date, watch battery + messages, stress, workday status.
    private function drawInfoBlock(dc as Graphics.Dc, minsNow as Number, workday as Boolean, inDay as Boolean) as Void {
        var font = Graphics.FONT_XTINY;
        var right = Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER;

        var d = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        dc.drawText(INFO_RIGHT, INFO_ROWS[0], font, (d.day_of_week as String).toUpper() + " " + d.day.format("%d"), right);

        // Watch battery days (the watch's own estimate, solar included) and unread notifications
        var stats = System.getSystemStats();
        var daysStr = "--";
        if (stats has :batteryInDays && stats.batteryInDays != null) {
            daysStr = (stats.batteryInDays as Float).toNumber().format("%d") + "d";
        }
        var count = System.getDeviceSettings().notificationCount;
        var countStr = count.format("%d");
        var y = INFO_ROWS[1];
        var x = INFO_RIGHT - dc.getTextWidthInPixels(countStr, font);
        dc.drawText(x, y, font, countStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x -= 3 + 13;
        drawEnvelope(dc, x, y, count > 0);
        x -= 8 + dc.getTextWidthInPixels(daysStr, font);
        dc.drawText(x, y, font, daysStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x -= 3 + 15;
        drawBattery(dc, x, y, stats.battery);

        var stress = newest(SensorHistory.getStressHistory({ :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST }));
        dc.drawText(INFO_RIGHT, INFO_ROWS[2], font, "STRESS " + (stress != null ? stress.format("%d") : "--"), right);

        var line;
        if (!workday) {
            line = "WEEKEND";
        } else if (inDay) {
            var left = _end * 60 - minsNow;
            line = (left / 60).format("%d") + "h" + (left % 60).format("%02d") + " LEFT";
        } else if (minsNow < _start * 60) {
            line = "PRE-WORK";
        } else {
            line = "OFF WORK";
        }
        dc.drawText(INFO_RIGHT, INFO_ROWS[3], font, line, right);
    }

    private function drawBattery(dc as Graphics.Dc, x as Number, y as Number, pct as Float) as Void {
        var bw = 13;
        var bh = 8;
        var by = y - bh / 2;
        dc.drawRectangle(x, by, bw, bh);
        dc.fillRectangle(x + bw, by + 2, 2, bh - 4);
        var fill = ((pct / 100.0) * (bw - 4)).toNumber();
        if (fill > 0) { dc.fillRectangle(x + 2, by + 2, fill, bh - 4); }
    }

    // Filled when something is unread (texts, email, any app your phone forwards to the watch).
    private function drawEnvelope(dc as Graphics.Dc, x as Number, y as Number, unread as Boolean) as Void {
        var iw = 13;
        var ih = 9;
        var iy = y - ih / 2;
        if (unread) {
            dc.fillRectangle(x, iy, iw, ih);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x + 1, iy + 1, x + iw / 2, iy + ih / 2 + 1);
            dc.drawLine(x + iw / 2, iy + ih / 2 + 1, x + iw - 1, iy + 1);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.drawRectangle(x, iy, iw, ih);
            dc.drawLine(x, iy, x + iw / 2, iy + ih / 2);
            dc.drawLine(x + iw / 2, iy + ih / 2, x + iw - 1, iy);
        }
    }

    // One cell per work hour, with the count to the right.
    // Past hours: solid if you hit the step goal, hollow if not.
    // Current hour: thick border, fills from the bottom as you walk. Future hours: a dot.
    private function drawHours(dc as Graphics.Dc, w as Number, hourNow as Number) as Void {
        var n = _end - _start;
        var gap = 3;
        var hit = 0;
        for (var i = 0; i < n; i++) { if (_hourSteps[i] >= _hourGoal) { hit += 1; } }
        var label = hit.format("%d") + "/" + n.format("%d");
        var font = Graphics.FONT_XTINY;
        var labelW = dc.getTextWidthInPixels(label, font);
        var cell = (140 - 7 - labelW - (n - 1) * gap) / n;
        if (cell > 12) { cell = 12; }
        if (cell < 6) { cell = 6; }
        var cellsW = n * cell + (n - 1) * gap;
        var x0 = (w - (cellsW + 7 + labelW)) / 2;
        var y = HOURS_Y - cell / 2;
        for (var i = 0; i < n; i++) {
            var x = x0 + i * (cell + gap);
            var hr = _start + i;
            var done = _hourSteps[i] >= _hourGoal;
            if (hr < hourNow) {
                if (done) { dc.fillRectangle(x, y, cell, cell); } else { dc.drawRectangle(x, y, cell, cell); }
            } else if (hr == hourNow) {
                dc.setPenWidth(2);
                dc.drawRectangle(x, y, cell, cell);
                dc.setPenWidth(1);
                var frac = _hourSteps[i].toFloat() / _hourGoal;
                if (frac > 1.0) { frac = 1.0; }
                var fh = (frac * (cell - 4)).toNumber();
                if (fh > 0) { dc.fillRectangle(x + 2, y + cell - 2 - fh, cell - 4, fh); }
            } else {
                dc.fillRectangle(x + cell / 2 - 1, y + cell / 2 - 1, 2, 2);
            }
        }
        dc.drawText(x0 + cellsW + 7, HOURS_Y, font, label, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // "SITTING 14m", "SIT 14m  5PM ~31" with a forecast, or a black MOVE bar
    // once you've sat past the limit during work hours.
    private function drawBottom(dc as Graphics.Dc, w as Number, nowSec as Number, minsNow as Number, inDay as Boolean) as Void {
        var mins = (nowSec - _lastMove) / 60;
        if (mins < 0) { mins = 0; }
        var sit = mins >= 60 ? (mins / 60).format("%d") + "h" + (mins % 60).format("%02d") : mins.format("%d") + "m";
        var font = Graphics.FONT_XTINY;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        if (inDay && mins >= _sitWarn) {
            dc.fillRectangle(24, BOTTOM_Y - 10, w - 48, 20);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, BOTTOM_Y, font, "MOVE  SAT " + sit, center);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            return;
        }
        var text = "SITTING " + sit;
        if (inDay) {
            var f = forecast(minsNow);
            if (f != null) { text = "SIT " + sit + "  " + endLabel() + " ~" + f.format("%d"); }
        }
        dc.drawText(w / 2, BOTTOM_Y, font, text, center);
    }

    // End of the workday as "5PM", or "17h" on a 24-hour watch.
    private function endLabel() as String {
        if (System.getDeviceSettings().is24Hour) { return (_end % 24).format("%d") + "h"; }
        var h12 = _end % 12 == 0 ? 12 : _end % 12;
        return h12.format("%d") + (_end < 12 || _end == 24 ? "AM" : "PM");
    }

    // Where Body Battery will be at the end of the workday if it keeps changing
    // at the rate of the last 1-2 hours.
    private function forecast(minsNow as Number) as Number? {
        var it = SensorHistory.getBodyBatteryHistory({ :period => new Time.Duration(2 * 3600), :order => SensorHistory.ORDER_NEWEST_FIRST });
        var first = it.next();
        if (first == null) { return null; }
        var fd = first.data;
        var fw = first.when;
        if (fd == null || fw == null) { return null; }
        var nowVal = fd.toFloat();
        var t0 = fw.value();
        var oldVal = -1.0;
        var oldT = t0;
        var s = it.next();
        while (s != null) {
            var sd = s.data;
            var sw = s.when;
            if (sd != null && sw != null) { oldVal = sd.toFloat(); oldT = sw.value(); }
            s = it.next();
        }
        if (oldVal < 0 || t0 - oldT < 3600) { return null; }
        var perMin = (nowVal - oldVal) / ((t0 - oldT) / 60.0);
        var out = nowVal + perMin * (_end * 60 - minsNow);
        if (out < 0) { out = 0; }
        if (out > 100) { out = 100; }
        return out.toNumber();
    }

    private function newest(it as SensorHistory.SensorHistoryIterator?) as Number? {
        if (it == null) { return null; }
        var s = it.next();
        while (s != null) {
            var v = s.data;
            if (v != null) { return v.toNumber(); }
            s = it.next();
        }
        return null;
    }

    private function formatThousands(n as Number) as String {
        if (n < 1000) { return n.format("%d"); }
        return (n / 1000).format("%d") + "," + (n % 1000).format("%03d");
    }

    // Body Battery in the round subscreen.
    private function drawSubscreen(dc as Graphics.Dc) as Void {
        var bb = newest(SensorHistory.getBodyBatteryHistory({ :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST }));
        var box = WatchUi.getSubscreen();
        if (box == null) { return; }
        var bx = box.x;
        var by = box.y;
        var bw = box.width;
        var bh = box.height;
        if (bx == null || by == null || bw == null || bh == null) { return; }
        var cx = bx + bw / 2;
        var cy = by + bh / 2;
        dc.fillCircle(cx, cy, bw / 2);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 5, Graphics.FONT_SMALL, bb != null ? bb.format("%d") : "--", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, cy + 14, Graphics.FONT_XTINY, "BODY", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
    }

    function onEnterSleep() as Void { WatchUi.requestUpdate(); }
    function onExitSleep() as Void { WatchUi.requestUpdate(); }
}
