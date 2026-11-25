// Turns the .FIT files copied off the watch into one compact JSON file for the dashboard.
// GPS positions are converted to metres relative to a shared origin, so no absolute
// coordinates end up in the output.
import { Decoder, Stream } from '@garmin/fitsdk';
import fs from 'fs';
import path from 'path';

const root = path.resolve(process.argv[2] || '../garmin-data');
const out = path.resolve(process.argv[3] || '../dashboard/data.json');
const FIT_EPOCH = 631065600; // 1989-12-31T00:00:00Z
const SEMI = 180 / 2 ** 31;
const R = 6371000;

const read = f => new Decoder(Stream.fromBuffer(fs.readFileSync(f))).read({ convertDateTimesToDates: true }).messages;
const r1 = (v, d = 1) => v == null ? null : Math.round(v * 10 ** d) / 10 ** d;

const rides = [];
const snapshots = [];
const actDir = path.join(root, 'Activity');
const parsed = fs.readdirSync(actDir).sort().map(f => ({ f, m: read(path.join(actDir, f)) }));

// Shared origin: mean start position of all GPS activities.
const starts = parsed.map(p => p.m.recordMesgs?.find(r => r.positionLat != null)).filter(Boolean);
const lat0 = starts.reduce((s, r) => s + r.positionLat * SEMI, 0) / starts.length;
const lon0 = starts.reduce((s, r) => s + r.positionLong * SEMI, 0) / starts.length;
const kx = Math.PI / 180 * R * Math.cos(lat0 * Math.PI / 180);
const ky = Math.PI / 180 * R;

for (const { f, m } of parsed) {
  const s = m.sessionMesgs?.[0];
  if (!s) continue;
  if (s.sportProfileName === 'Health Snapshot' || s.sport === 60) {
    snapshots.push({
      start: s.startTime.toISOString(), hr: s.avgHeartRate, maxHr: s.maxHeartRate,
      rmssd: s.rmssdHrv, sdrr: s.sdrrHrv, spo2: s.avgSpo2, stress: s.avgStress,
      resp: r1(s.enhancedAvgRespirationRate),
      series: (m.recordMesgs || []).map(r => [Math.round((r.timestamp - s.startTime) / 1000), r.heartRate ?? null, r.currentStress ?? null, r1(r.enhancedRespirationRate)]),
    });
    continue;
  }
  const t0 = s.startTime.getTime();
  let lastKept = -Infinity;
  const pts = [];
  for (const r of m.recordMesgs || []) {
    if (r.positionLat == null) continue;
    const t = (r.timestamp - t0) / 1000;
    if (t - lastKept < 2) continue; // ~1 point every 2 s keeps the file small
    lastKept = t;
    pts.push([
      Math.round(t),
      Math.round((r.positionLong * SEMI - lon0) * kx),
      Math.round((r.positionLat * SEMI - lat0) * ky),
      r.heartRate ?? null,
      r1(r.enhancedSpeed, 2),
      r1(r.enhancedAltitude),
      Math.round(r.distance ?? 0),
    ]);
  }
  const zones = m.timeInZoneMesgs?.find(z => z.referenceMesg === 'session');
  rides.push({
    file: f, start: s.startTime.toISOString(), profile: s.sportProfileName, sport: s.sport, subSport: s.subSport,
    distance: r1(s.totalDistance), timer: r1(s.totalTimerTime), elapsed: r1(s.totalElapsedTime),
    avgSpeed: r1(s.enhancedAvgSpeed, 2), maxSpeed: r1(s.enhancedMaxSpeed, 2),
    avgHr: s.avgHeartRate, maxHr: s.maxHeartRate, ascent: s.totalAscent, descent: s.totalDescent,
    calories: s.totalCalories, te: s.totalTrainingEffect, anTe: s.totalAnaerobicTrainingEffect,
    minAlt: r1(s.enhancedMinAltitude), maxAlt: r1(s.enhancedMaxAltitude),
    zones: zones ? { secs: zones.timeInHrZone.slice(0, 6).map(v => Math.round(v)), bounds: zones.hrZoneHighBoundary } : null,
    laps: (m.lapMesgs || []).map(l => ({ dist: r1(l.totalDistance), timer: r1(l.totalTimerTime), avgHr: l.avgHeartRate })),
    pts,
  });
}

// Today's all-day monitoring file.
const today = { hr: [], stress: [], resp: [], steps: [], activity: [] };
const monDir = path.join(root, 'Monitor');
for (const f of fs.readdirSync(monDir)) {
  const m = read(path.join(monDir, f));
  today.restingHr = m.monitoringHrDataMesgs?.at(-1)?.currentDayRestingHeartRate;
  let lastFit = null;
  const cyclesByType = {};
  for (const r of m.monitoringMesgs || []) {
    let fit;
    if (r.timestamp) fit = lastFit = Math.round(r.timestamp.getTime() / 1000) - FIT_EPOCH;
    else if (r.timestamp16 != null && lastFit != null) fit = lastFit += ((r.timestamp16 - (lastFit & 0xffff)) & 0xffff);
    if (fit == null) continue;
    const iso = (fit + FIT_EPOCH) * 1000;
    if (r.heartRate) today.hr.push([iso, r.heartRate]);
    if (r.cycles != null && r.activityType) {
      cyclesByType[r.activityType] = r.cycles;
      const steps = (cyclesByType.walking || 0) * 2 + (cyclesByType.running || 0) * 2;
      today.steps.push([iso, steps]);
    }
    if (r.intensity != null && r.activityType) today.activity.push([iso, r.activityType, r.intensity]);
  }
  for (const s of m.stressLevelMesgs || []) if (s.stressLevelValue >= 0) today.stress.push([s.stressLevelTime.getTime(), s.stressLevelValue]);
  for (const s of m.respirationRateMesgs || []) if (s.respirationRate > 0) today.resp.push([s.timestamp.getTime(), r1(s.respirationRate)]);
}
today.hr.sort((a, b) => a[0] - b[0]);
today.steps.sort((a, b) => a[0] - b[0]);

const tot = read(path.join(root, 'Totals', 'Totals.fit')).totalsMesgs || [];
const all = tot.find(t => t.sport == null) || {};
const device = { model: 'Instinct 2X Solar' };

const data = { generated: new Date().toISOString(), device, units: 'statute', rides, snapshots, today,
  totals: { sessions: all.sessions, distance: all.distance, timerTime: all.timerTime, calories: all.calories } };
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify(data));
console.log(`rides ${rides.length} (${rides.map(r => r.pts.length).join(',')} pts), snapshots ${snapshots.length}, hr ${today.hr.length}, stress ${today.stress.length}, steps ${today.steps.at(-1)?.[1]}, resting ${today.restingHr}`);
console.log('bytes', fs.statSync(out).size);
