import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { NextClassSnapshot } from '../feature/widget/NextClassModel';
import { NextClassWidgetService } from '../feature/widget/NextClassWidgetService';

// The system supplies the requested size through Want, not through the card's LocalStorage.
// Only the initial binding includes it; subsequent schedule updates preserve each instance's size.
class NextClassInitialData extends NextClassSnapshot {
  formDimension: number = 2;
  courseOnly: boolean = false;
}

export default class NextClassFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const initial = new NextClassInitialData();
    const name = String(want.parameters?.[formInfo.FormParam.NAME_KEY] ?? '');
    initial.courseOnly = name === 'LessonCountdownCard';
    initial.formDimension = Number(want.parameters?.[formInfo.FormParam.DIMENSION_KEY] ?? 2);
    const formId = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    if (formId.length > 0) void NextClassWidgetService.refreshForm(this.context, formId, name);
    return formBindingData.createFormBindingData(initial);
  }

  onUpdateForm(formId: string): void {
    void NextClassWidgetService.refreshForm(this.context, formId);
  }

  onCastToNormalForm(formId: string): void {
    void NextClassWidgetService.refreshForm(this.context, formId);
  }

  onFormEvent(formId: string, _message: string): void {
    void NextClassWidgetService.refreshForm(this.context, formId);
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  onRemoveForm(_formId: string): void {
    // Instance discovery comes from the system; no retained form IDs or background timers.
  }
}
