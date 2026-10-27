/** Shared colors used by the login, navigation and timetable management views. */
export class HitaColors {
  static readonly primary: Resource = $r('app.color.hita_primary');
  static readonly primaryFill: Resource = $r('app.color.hita_primary_fill');
  static readonly onPrimary: ResourceColor = '#FFFFFF';
  /** Brand tint behind selected items, secondary buttons and list icons. */
  static readonly selected: Resource = $r('app.color.hita_selected');
  static readonly onSurface: ResourceColor = $r('app.color.hita_text');
  static readonly onSurfaceVariant: ResourceColor = $r('app.color.hita_text_secondary');
  static readonly control: Resource = $r('app.color.hita_control');
  static readonly error: Resource = $r('app.color.hita_error');
  static readonly errorSurface: Resource = $r('app.color.hita_error_surface');
  static readonly divider: ResourceColor = $r('app.color.hita_divider');
}
