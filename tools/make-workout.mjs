// Builds a heart-rate-zone interval workout for the e-bike as a .FIT workout file.
// Zones are the watch's own (Z2 = 98-116, Z3 = 117-135, Z4 = 136-154 bpm).
import { Encoder, Decoder, Stream, Profile } from '@garmin/fitsdk';
import fs from 'fs';
import path from 'path';

const out = path.resolve(process.argv[2] || '../workout/EBIKEZN.FIT');
const NAME = 'E-Bike Zone Builder';
const min = m => m * 60 * 1000; // durationValue for time steps is milliseconds

const steps = [
  { wktStepName: 'Warm up', intensity: 'warmup', durationType: 'time', durationValue: min(10), targetType: 'heartRate', targetValue: 2 },
  { wktStepName: 'Push Z3', intensity: 'active', durationType: 'time', durationValue: min(4), targetType: 'heartRate', targetValue: 3 },
  { wktStepName: 'Easy Z2', intensity: 'recovery', durationType: 'time', durationValue: min(3), targetType: 'heartRate', targetValue: 2 },
  { wktStepName: 'Repeat', durationType: 'repeatUntilStepsCmplt', durationValue: 1, targetType: 'open', targetValue: 4 },
  { wktStepName: 'Surge Z4', intensity: 'active', durationType: 'time', durationValue: min(2), targetType: 'heartRate', targetValue: 4 },
  { wktStepName: 'Cool down', intensity: 'cooldown', durationType: 'time', durationValue: min(10), targetType: 'heartRate', targetValue: 1 },
];

const enc = new Encoder();
enc.onMesg(Profile.MesgNum.FILE_ID, { type: 'workout', manufacturer: 'development', product: 0, serialNumber: 1, timeCreated: new Date() });
enc.onMesg(Profile.MesgNum.WORKOUT, { wktName: NAME, sport: 'cycling', subSport: 'eBikeFitness', numValidSteps: steps.length });
steps.forEach((s, i) => enc.onMesg(Profile.MesgNum.WORKOUT_STEP, { messageIndex: i, customTargetValueLow: 0, customTargetValueHigh: 0, ...s }));
const bytes = enc.close();
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, bytes);

// Read it back to make sure it decodes cleanly
const d = new Decoder(Stream.fromByteArray(bytes));
console.log('valid FIT:', d.isFIT(), 'integrity:', d.checkIntegrity());
const { messages, errors } = new Decoder(Stream.fromByteArray(bytes)).read();
console.log('errors:', errors);
console.log(JSON.stringify(messages.workoutMesgs), '\n' + messages.workoutStepMesgs.map(s => JSON.stringify(s)).join('\n'));
const total = 10 + 4 * (4 + 3) + 2 + 10;
console.log(`${out} (${bytes.length} bytes), ~${total} min`);
