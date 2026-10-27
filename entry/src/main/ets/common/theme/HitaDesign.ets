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
  /** Spacing scale on a 4 vp grid; inset, gap and sectionGap below are its semantic aliases. */
  static readonly space2xs: number = 4;
  static readonly spaceXs: number = 8;
  static readonly spaceSm: number = 12;
  static readonly spaceMd: number = 16;
  static readonly spaceLg: number = 24;
  static readonly spaceXl: number = 32;
  static readonly inset: number = 16;
  static readonly gap: number = 12;
  static readonly sectionGap: number = 24;
  /** Corner scale. Nested corners subtract the parent's padding; capsules use half their height. */
  static readonly radiusSm: number = 8;
  static readonly radiusMd: number = 12;
  static readonly radiusLg: number = 16;
  static readonly radiusXl: number = 24;
  static readonly cardRadius: number = 16;
  static readonly fieldRadius: number = 12;
  static readonly heroRadius: number = 24;
  static readonly buttonHeight: number = 48;
  /** Inline buttons and segmented items. */
  static readonly controlHeight: number = 40;
  /** Text actions beside a 44 vp header back button. */
  static readonly compactControlHeight: number = 36;
  /** Smallest tap area; compact controls extend their response region to it. */
  static readonly minTouchTarget: number = 44;
  /** Two-line list row with a 40 vp icon. */
  static readonly rowMinHeight: number = 64;
  static readonly listIconSize: number = 40;
  /** Row dividers start where the row text starts: row inset + icon + text gap. */
  static readonly listTextInset: number = 68;
  static readonly hairline: number = 0.5;
  static readonly headerHeight: number = 64;
  static readonly contentMaxWidth: number = 720;
}
