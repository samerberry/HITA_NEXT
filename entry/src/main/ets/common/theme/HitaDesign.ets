/** Shared layout and typography for application pages; timetable cells retain their compact scale. */
export class HitaDesign {
  /** Large standalone metrics; ordinary page headings use title. */
  static readonly display: number = 28;
  static readonly title: number = 22;
  static readonly section: number = 18;
  static readonly body: number = 16;
  /** Dates, places, teachers, field labels and other readable supporting text. */
  static readonly caption: number = 14;
  /** Short badges only; never use for a sentence or a field label. */
  static readonly label: number = 12;
  static readonly iconXs: number = 12;
  static readonly iconSm: number = 16;
  static readonly iconMd: number = 20;
  static readonly iconLg: number = 24;
  static readonly iconXl: number = 32;
  static readonly inset: number = 16;
  static readonly gap: number = 12;
  static readonly sectionGap: number = 24;
  static readonly cardRadius: number = 16;
  static readonly fieldRadius: number = 12;
  static readonly heroRadius: number = 24;
  static readonly buttonHeight: number = 48;
  static readonly rowMinHeight: number = 72;
  static readonly headerHeight: number = 64;
  static readonly contentMaxWidth: number = 720;
}
