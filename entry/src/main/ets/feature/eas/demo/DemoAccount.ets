import { EasCampus, EasSession } from '../EasSession';

/** The selected campus scopes the session. All campuses share the built-in samples. */
export class DemoAccount {
  static createSession(campus: EasCampus = EasCampus.SHENZHEN): EasSession {
    const session = new EasSession();
    session.demoMode = true;
    session.campus = campus;
    return session;
  }

  static isSession(session: EasSession | undefined): boolean {
    return session?.demoMode === true;
  }
}
