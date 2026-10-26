import { EasTimetable, EasTermSubject, EasEventItem, EasImportBaseEntry } from './TimetableModels';

export class TimetableBackup {
  timetable: EasTimetable = new EasTimetable();
  subjects: EasTermSubject[] = [];
  events: EasEventItem[] = [];
  importBase: EasImportBaseEntry[] = [];
}
