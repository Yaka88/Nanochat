import path from 'path';
import fs from 'fs/promises';
import { fileURLToPath } from 'url';
import { v4 as uuidv4 } from 'uuid';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads');

export async function ensureUploadsDir() {
    await fs.mkdir(UPLOADS_DIR, { recursive: true });
}

export async function saveFile(buffer: Buffer, extension: string): Promise<string> {
    await ensureUploadsDir();

    const filename = `${uuidv4()}${extension}`;
    const filepath = path.join(UPLOADS_DIR, filename);

    await fs.writeFile(filepath, buffer);

    return `/uploads/${filename}`;
}

export async function deleteFile(url: string): Promise<void> {
    const filename = path.basename(url);
    if (!filename || filename.includes('..')) {
        return;
    }
    const filepath = path.join(UPLOADS_DIR, filename);

    try {
        await fs.unlink(filepath);
    } catch (error) {
        // Ignore if file doesn't exist
    }
}
