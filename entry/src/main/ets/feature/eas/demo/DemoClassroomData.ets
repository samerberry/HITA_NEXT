import { ClassroomBuilding, ClassroomRoom, ClassroomSlot } from '../classroom/EmptyClassroomData';
import { EasTermItem } from '../model/EasModels';

/** Building/room names transcribed from the supplied Shenzhen recording; occupancy is synthetic. */
export class DemoClassroomData {
  static buildings(): ClassroomBuilding[] {
    const names: string[] = ['A楼', 'F楼', 'G楼', '体育场地', '经管楼', '大学城国际一期', '实训楼',
      '教学楼II', '教学楼III', '教学楼IV', '教学楼V', '教学楼VI', '主楼', '活动中心', 'L楼',
      '北大教学楼', '信息楼', '清华教学楼', '南科大教学楼', '深职大教学楼', '深大教学楼', '国设楼', '其它'];
    return names.map((name: string, index: number): ClassroomBuilding => {
      const building: ClassroomBuilding = new ClassroomBuilding();
      building.id = 'demo-sz-' + index.toString();
      building.name = name;
      building.area = 'demo-shenzhen';
      return building;
    });
  }

  private static roomNames(name: string): string[] {
    switch (name) {
      case 'A楼': return ['A103', 'A109', 'A405', 'A416'];
      case 'G楼': return ['G707'];
      case '经管楼': return ['M701', 'M702', 'M802', 'M806', 'M807', 'M808'];
      case '教学楼II': return ['T2304', 'T2306', 'T2307', 'T2309', 'T2313', 'T2407', 'T2803'];
      case '教学楼III': return ['T3201', 'T3202', 'T3401', 'T3402', 'T3501', 'T3502'];
      case '教学楼IV': return ['T4402'];
      case '教学楼V': return ['T5204', 'T5205', 'T5206', 'T5304', 'T5305', 'T5306', 'T5404', 'T5405',
        'T5406', 'T5503', 'T5505', 'T5506', 'T5507', 'T5603', 'T5605', 'T5606'];
      case '教学楼VI': return ['T6401', 'T6404', 'T6405', 'T6406'];
      case '主楼': return ['H301', 'H302', 'H303', 'H304', 'H307', 'H308', 'H311', 'H312', 'H313',
        'H401', 'H402', 'H403', 'H404', 'H407', 'H408', 'H411', 'H412', 'H413', 'H501', 'H502',
        'H503', 'H504', 'H507', 'H508', 'H509', 'H512', 'H513'];
      default: return [];
    }
  }

  static query(term: EasTermItem, building: ClassroomBuilding, week: number): ClassroomRoom[] {
    if (term.yearCode !== '2026-2027' || term.termCode !== '1') { return []; }
    const known: ClassroomBuilding | undefined = DemoClassroomData.buildings().find(
      (candidate: ClassroomBuilding): boolean => candidate.key() === building.key());
    if (known === undefined) { return []; }
    return DemoClassroomData.roomNames(known.name).map((name: string, index: number): ClassroomRoom => {
      const room: ClassroomRoom = new ClassroomRoom();
      room.id = known.id + ':' + name;
      room.name = name;
      room.periodCount = 12;
      // Stable per room/week so refreshes and cached results agree. Weekend/evening slots remain free.
      let seed: number = week;
      for (let i: number = 0; i < name.length; i++) { seed += name.charCodeAt(i); }
      for (let day: number = 1; day <= 5; day++) {
        for (let block: number = 0; block < 5; block++) {
          if ((seed + day * 3 + block + index) % 4 !== 0) { continue; }
          for (let offset: number = 1; offset <= 2; offset++) {
            const slot: ClassroomSlot = new ClassroomSlot();
            slot.day = day;
            slot.period = block * 2 + offset;
            room.occupied.push(slot);
          }
        }
      }
      return room;
    });
  }
}
