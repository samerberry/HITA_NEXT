/** Android-style timetable import route. */
import { ImportTimetablePanel } from './ImportTimetablePanel';

@Entry
@Component
struct ImportTimetablePage {
  build() {
    Column() {
      ImportTimetablePanel({ presentedAsSheet: false })
        .width('100%')
        .height('100%');
    }
    .width('100%')
    .height('100%');
  }
}
