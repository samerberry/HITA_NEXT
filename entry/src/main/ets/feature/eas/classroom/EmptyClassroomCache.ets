import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { EasSession } from '../EasSession';
import { DemoAccount } from '../demo/DemoAccount';
import { EasTermItem } from '../model/EasModels';
import { ClassroomBuilding, ClassroomRoom } from './EmptyClassroomData';

export class ClassroomSnapshot {
  savedAt: number = 0;
  rooms: ClassroomRoom[] = [];
}

/** Android's cache-then-network flow, scoped to account/campus as well as query. */
export class EmptyClassroomCache {
  static readonly MAX_AGE: number = 180 * 24 * 60 * 60 * 1000;
  private store: preferences.Preferences | undefined = undefined;

  async init(context: common.Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, { name: 'hita_classroom_cache_v1' });
    } catch (e) {
      this.store = undefined;
    }
  }

  static key(session: EasSession, term: EasTermItem, building: ClassroomBuilding, week: number): string {
    const scope: string = DemoAccount.isSession(session) ? 'demo-v1:' : '';
    return scope + JSON.stringify([session.campus, session.getStudentType(), session.stuId || session.username,
      term.getCode(), building.area, building.id, week.toString()]);
  }

  async read(key: string): Promise<ClassroomSnapshot | undefined> {
    if (this.store === undefined) {
      return undefined;
    }
    try {
      const raw: string = String(await this.store.get(key, ''));
      const snapshot: ClassroomSnapshot = JSON.parse(raw) as ClassroomSnapshot;
      if (snapshot === null || !Number.isFinite(snapshot.savedAt) || snapshot.savedAt <= 0 ||
        Date.now() - snapshot.savedAt > EmptyClassroomCache.MAX_AGE || !Array.isArray(snapshot.rooms)) {
        return undefined;
      }
      for (let i: number = 0; i < snapshot.rooms.length; i++) {
        const room: ClassroomRoom = snapshot.rooms[i];
        if (room === null || typeof room.name !== 'string' || typeof room.id !== 'string' ||
          !Array.isArray(room.occupied) || !Array.isArray(room.unknown) || !Number.isInteger(room.periodCount)) {
          return undefined;
        }
      }
      return snapshot;
    } catch (e) {
      return undefined;
    }
  }

  async write(key: string, rooms: ClassroomRoom[]): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    try {
      const snapshot: ClassroomSnapshot = new ClassroomSnapshot();
      snapshot.savedAt = Date.now();
      snapshot.rooms = rooms;
      await this.store.put(key, JSON.stringify(snapshot));
      // Same 180-day retention as Android; invalid entries can also be removed safely.
      const all: Object = await this.store.getAll();
      const keys: string[] = Object.keys(all);
      for (let i: number = 0; i < keys.length; i++) {
        if (keys[i] !== key && await this.read(keys[i]) === undefined) {
          await this.store.delete(keys[i]);
        }
      }
      await this.store.flush();
    } catch (e) {
      // Cache failures must not turn a successful remote query into an error.
    }
  }
}
