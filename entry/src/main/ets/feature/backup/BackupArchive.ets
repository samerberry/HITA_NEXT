import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BackupAsset, BackupManifest, BackupModel } from './BackupModel';

const MAGIC: string = 'HITABK01';
const HEADER_SIZE: number = 44;
const CHUNK_SIZE: number = 1024 * 1024;

export class BackupSource {
  role: string = '';
  path: string = '';
  constructor(role: string, path: string) { this.role = role; this.path = path; }
}

export class PreparedBackup {
  manifest: BackupManifest = new BackupManifest();
  directory: string = '';
}

/** Streaming container: fixed header, bounded UTF-8 metadata, then the five allowlisted media streams.
 * No embedded paths, archive extraction, base64 or full-video allocations. SHA-256 covers metadata and every asset.
 */
export class BackupArchive {
  static async verify(prepared: PreparedBackup): Promise<void> {
    BackupModel.parse(JSON.stringify(prepared.manifest));
    for (const asset of prepared.manifest.assets) {
      const file = await fileIo.open(prepared.directory + '/' + asset.role, fileIo.OpenMode.READ_ONLY);
      try {
        if (fileIo.statSync(file.fd).size !== asset.size ||
          await BackupArchive.transfer(file.fd, -1, asset.size) !== asset.sha256) throw new Error('背景文件校验失败，请重新选择备份');
      } finally { await fileIo.close(file); }
    }
  }

  static async create(path: string, manifest: BackupManifest, sources: BackupSource[],
    progress: (message: string) => void): Promise<void> {
    manifest.assets = [];
    for (const source of sources) {
      progress('正在读取背景文件');
      const asset = new BackupAsset();
      asset.role = source.role;
      const file = await fileIo.open(source.path, fileIo.OpenMode.READ_ONLY);
      try {
        asset.size = fileIo.statSync(file.fd).size;
        asset.sha256 = await BackupArchive.transfer(file.fd, -1, asset.size);
      } finally { await fileIo.close(file); }
      manifest.assets.push(asset);
    }
    BackupModel.parse(JSON.stringify(manifest));
    const encoded = buffer.from(JSON.stringify(manifest), 'utf-8');
    const metadata = new Uint8Array(encoded.buffer.slice(encoded.byteOffset, encoded.byteOffset + encoded.length));
    if (metadata.length > BackupModel.MAX_MANIFEST) throw new Error('课表数据过多，无法创建备份');
    const header = new Uint8Array(HEADER_SIZE);
    for (let i = 0; i < MAGIC.length; i++) header[i] = MAGIC.charCodeAt(i);
    new DataView(header.buffer).setUint32(8, metadata.length, true);
    header.set(await BackupArchive.digest(metadata), 12);
    const out = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      await BackupArchive.writeAll(out.fd, header.buffer as ArrayBuffer);
      await BackupArchive.writeAll(out.fd, metadata.buffer as ArrayBuffer);
      for (let i = 0; i < sources.length; i++) {
        progress('正在打包背景 ' + (i + 1).toString() + '/' + sources.length.toString());
        const input = await fileIo.open(sources[i].path, fileIo.OpenMode.READ_ONLY);
        try {
          const asset = manifest.assets[i];
          if (fileIo.statSync(input.fd).size !== asset.size ||
            await BackupArchive.transfer(input.fd, out.fd, asset.size) !== asset.sha256) {
            throw new Error('背景文件已变化，请重新备份');
          }
        } finally { await fileIo.close(input); }
      }
      await fileIo.fsync(out.fd);
    } finally { await fileIo.close(out); }
  }

  static async prepare(uri: string, directory: string, progress: (message: string) => void): Promise<PreparedBackup> {
    const input = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = fileIo.statSync(input.fd).size;
      const header = await BackupArchive.readExact(input.fd, HEADER_SIZE);
      if (buffer.from(header.slice(0, 8)).toString('utf-8') !== MAGIC) throw new Error('请选择 HITA NEXT 备份文件');
      const length = new DataView(header).getUint32(8, true);
      if (length < 2 || length > BackupModel.MAX_MANIFEST || length > size - HEADER_SIZE) {
        throw new Error('备份文件已损坏');
      }
      const metadata = await BackupArchive.readExact(input.fd, length);
      if (BackupArchive.hex(await BackupArchive.digest(new Uint8Array(metadata))) !==
        BackupArchive.hex(new Uint8Array(header.slice(12)))) throw new Error('备份文件校验失败');
      const manifest = BackupModel.parse(buffer.from(metadata).toString('utf-8'));
      let expected = HEADER_SIZE + length;
      for (const asset of manifest.assets) expected += asset.size;
      if (!Number.isSafeInteger(expected) || expected !== size) throw new Error('备份文件不完整或已损坏');
      fileIo.mkdirSync(directory, true);
      for (let i = 0; i < manifest.assets.length; i++) {
        progress('正在校验背景 ' + (i + 1).toString() + '/' + manifest.assets.length.toString());
        const asset = manifest.assets[i];
        const output = await fileIo.open(directory + '/' + asset.role,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try {
          if (await BackupArchive.transfer(input.fd, output.fd, asset.size) !== asset.sha256) {
            throw new Error('背景文件校验失败，备份可能已损坏');
          }
        } finally { await fileIo.close(output); }
      }
      const result = new PreparedBackup();
      result.manifest = manifest;
      result.directory = directory;
      return result;
    } finally { await fileIo.close(input); }
  }

  private static async digest(data: Uint8Array): Promise<Uint8Array> {
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: data });
    return (await digest.digest()).data;
  }

  private static hex(bytes: Uint8Array): string {
    return buffer.from(bytes).toString('hex');
  }

  private static async transfer(input: number, output: number, size: number): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256');
    let remaining = size;
    while (remaining > 0) {
      const chunk = await BackupArchive.readExact(input, Math.min(remaining, CHUNK_SIZE));
      await digest.update({ data: new Uint8Array(chunk) });
      if (output >= 0) await BackupArchive.writeAll(output, chunk);
      remaining -= chunk.byteLength;
    }
    return BackupArchive.hex((await digest.digest()).data);
  }

  private static async readExact(fd: number, length: number): Promise<ArrayBuffer> {
    const data = new Uint8Array(length);
    let position = 0;
    while (position < length) {
      const piece = new ArrayBuffer(length - position);
      const read = await fileIo.read(fd, piece);
      if (read <= 0) throw new Error('备份文件不完整');
      data.set(new Uint8Array(piece, 0, read), position);
      position += read;
    }
    return data.buffer;
  }

  private static async writeAll(fd: number, data: ArrayBuffer): Promise<void> {
    let position = 0;
    while (position < data.byteLength) {
      const written = await fileIo.write(fd, data.slice(position));
      if (written <= 0) throw new Error('文件写入失败，请检查可用空间');
      position += written;
    }
  }
}
