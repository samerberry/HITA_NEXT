import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';

export class TimetableBackground {
  imagePath: string = '';
  videoPath: string = '';
}

const FILE_NAME: string = 'timetable-background.jpg';
const MANIFEST: string = '/timetable-background.json';

export class TimetableBackgroundStore {
  static destPath(context: common.Context): string { return context.filesDir + '/' + FILE_NAME; }

  static load(context: common.Context): TimetableBackground {
    try {
      const saved = JSON.parse(fileIo.readTextSync(context.filesDir + MANIFEST)) as TimetableBackground;
      if (saved.imagePath === '') return new TimetableBackground();
      if (saved.imagePath && fileIo.accessSync(saved.imagePath)) {
        if (saved.videoPath && !fileIo.accessSync(saved.videoPath)) saved.videoPath = '';
        return saved;
      }
    } catch (_) {}
    const result = new TimetableBackground();
    if (TimetableBackgroundStore.exists(TimetableBackgroundStore.destPath(context))) {
      result.imagePath = TimetableBackgroundStore.destPath(context);
    }
    return result;
  }

  static loadPath(context: common.Context): string { return TimetableBackgroundStore.load(context).imagePath; }
  static toDisplayUri(path: string): string { return 'file://' + path + '#' + Date.now().toString(); }

  private static exists(path: string): boolean {
    try { return path.length > 0 && fileIo.accessSync(path); } catch (_) { return false; }
  }

  private static deleteFile(path: string): void {
    try { if (TimetableBackgroundStore.exists(path)) fileIo.unlinkSync(path); } catch (_) {}
  }

  // Publish only after copying and decoding succeeds; cancellation leaves the old wallpaper intact.
  static async pickAndSave(context: common.UIAbilityContext, video: boolean = false): Promise<TimetableBackground | undefined> {
    const options = new picker.PhotoSelectOptions();
    options.MIMEType = video ? picker.PhotoViewMIMETypes.VIDEO_TYPE : picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const picked = await new picker.PhotoViewPicker(context).select(options);
    if (!picked || !picked.photoUris || picked.photoUris.length === 0) return undefined;
    const base = context.filesDir + '/timetable-background-' + Date.now().toString();
    const next = new TimetableBackground();
    next.imagePath = base + '.jpg';
    next.videoPath = video ? base + '.video' : '';
    const temporaryManifest = context.filesDir + MANIFEST + '.tmp';
    try {
      const source = await fileIo.open(picked.photoUris[0], fileIo.OpenMode.READ_ONLY);
      try {
        const target = await fileIo.open(video ? next.videoPath : next.imagePath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try { await fileIo.copyFile(source.fd, target.fd); } finally { await fileIo.close(target); }
      } finally { await fileIo.close(source); }
      if (video) await TimetableBackgroundStore.createCover(next);
      const previous = TimetableBackgroundStore.load(context);
      const manifest = fileIo.openSync(temporaryManifest,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(manifest.fd, JSON.stringify(next)); } finally { fileIo.closeSync(manifest); }
      fileIo.renameSync(temporaryManifest, context.filesDir + MANIFEST);
      TimetableBackgroundStore.deleteFile(previous.imagePath);
      TimetableBackgroundStore.deleteFile(previous.videoPath);
      return next;
    } catch (error) {
      TimetableBackgroundStore.deleteFile(next.imagePath);
      TimetableBackgroundStore.deleteFile(next.videoPath);
      TimetableBackgroundStore.deleteFile(temporaryManifest);
      throw new Error(String(error));
    }
  }

  private static async createCover(background: TimetableBackground): Promise<void> {
    const source = await fileIo.open(background.videoPath, fileIo.OpenMode.READ_ONLY);
    let generator: media.AVImageGenerator | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    let packer: image.ImagePacker | undefined = undefined;
    try {
      generator = await media.createAVImageGenerator();
      generator.fdSrc = { fd: source.fd, offset: 0, length: fileIo.statSync(source.fd).size };
      pixels = await generator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, {});
      packer = image.createImagePacker();
      const cover = await fileIo.open(background.imagePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try { await packer.packToFile(pixels, cover.fd, { format: 'image/jpeg', quality: 90 }); }
      finally { await fileIo.close(cover); }
    } finally {
      // Each release must run even when another resource fails to release.
      try { if (packer) await packer.release(); } finally {
        try { if (pixels) await pixels.release(); } finally {
          try { if (generator) await generator.release(); } finally { await fileIo.close(source); }
        }
      }
    }
  }

  static remove(context: common.Context): void {
    const current = TimetableBackgroundStore.load(context);
    // Remove selection before its media; never resurrect a legacy wallpaper.
    TimetableBackgroundStore.deleteFile(TimetableBackgroundStore.destPath(context));
    TimetableBackgroundStore.deleteFile(context.filesDir + MANIFEST);
    TimetableBackgroundStore.deleteFile(current.imagePath);
    TimetableBackgroundStore.deleteFile(current.videoPath);
  }
}
