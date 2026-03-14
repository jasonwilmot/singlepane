/**
 * File operation utilities for the Velocity file manager.
 * Handles copy, move, rename, and batch operations with
 * progress tracking and conflict resolution.
 */

const fs = require('fs/promises');
const path = require('path');
const crypto = require('crypto');
const { EventEmitter } = require('events');

const CHUNK_SIZE = 64 * 1024; // 64KB chunks for hashing
const COPY_BUFFER_SIZE = 1024 * 1024; // 1MB copy buffer

class FileOperationQueue extends EventEmitter {
  constructor(options = {}) {
    super();
    this.concurrency = options.concurrency || 4;
    this.running = 0;
    this.queue = [];
    this.operations = new Map();
    this.paused = false;
  }

  enqueue(operation) {
    const id = crypto.randomUUID();
    const entry = {
      id,
      operation,
      status: 'pending',
      progress: 0,
      startTime: null,
      error: null,
    };
    this.operations.set(id, entry);
    this.queue.push(entry);
    this.emit('enqueued', { id, operation });
    this._processNext();
    return id;
  }

  pause(id) {
    const entry = this.operations.get(id);
    if (entry && entry.status === 'running') {
      entry.status = 'paused';
      entry.operation.abort?.();
      this.emit('paused', { id });
    }
  }

  resume(id) {
    const entry = this.operations.get(id);
    if (entry && entry.status === 'paused') {
      entry.status = 'pending';
      this.queue.unshift(entry);
      this._processNext();
      this.emit('resumed', { id });
    }
  }

  cancel(id) {
    const entry = this.operations.get(id);
    if (entry) {
      entry.status = 'cancelled';
      entry.operation.abort?.();
      this.emit('cancelled', { id });
    }
  }

  async _processNext() {
    if (this.paused || this.running >= this.concurrency) return;
    const entry = this.queue.shift();
    if (!entry) return;

    this.running++;
    entry.status = 'running';
    entry.startTime = Date.now();

    try {
      await entry.operation.execute((progress) => {
        entry.progress = progress;
        this.emit('progress', { id: entry.id, progress });
      });
      entry.status = 'completed';
      entry.progress = 100;
      this.emit('completed', { id: entry.id });
    } catch (err) {
      entry.status = 'failed';
      entry.error = err;
      this.emit('failed', { id: entry.id, error: err });
    } finally {
      this.running--;
      this._processNext();
    }
  }

  getStatus() {
    return Array.from(this.operations.values()).map(({ id, status, progress, error }) => ({
      id, status, progress, error: error?.message,
    }));
  }
}

async function computeFileHash(filePath, algorithm = 'sha256') {
  const handle = await fs.open(filePath, 'r');
  const hash = crypto.createHash(algorithm);
  const buffer = Buffer.alloc(CHUNK_SIZE);

  try {
    let bytesRead;
    do {
      ({ bytesRead } = await handle.read(buffer, 0, CHUNK_SIZE));
      if (bytesRead > 0) {
        hash.update(buffer.subarray(0, bytesRead));
      }
    } while (bytesRead > 0);
  } finally {
    await handle.close();
  }

  return hash.digest('hex');
}

async function findDuplicates(dirPath, options = {}) {
  const { recursive = true, minSize = 1 } = options;
  const sizeMap = new Map();
  const duplicates = [];

  async function walk(dir) {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory() && recursive) {
        await walk(fullPath);
      } else if (entry.isFile()) {
        const stat = await fs.stat(fullPath);
        if (stat.size >= minSize) {
          const key = stat.size.toString();
          if (!sizeMap.has(key)) {
            sizeMap.set(key, []);
          }
          sizeMap.get(key).push(fullPath);
        }
      }
    }
  }

  await walk(dirPath);

  // Only hash files with matching sizes
  for (const [, files] of sizeMap) {
    if (files.length < 2) continue;
    const hashGroups = new Map();
    for (const file of files) {
      const hash = await computeFileHash(file);
      if (!hashGroups.has(hash)) {
        hashGroups.set(hash, []);
      }
      hashGroups.get(hash).push(file);
    }
    for (const [hash, group] of hashGroups) {
      if (group.length > 1) {
        duplicates.push({ hash, files: group });
      }
    }
  }

  return duplicates;
}

function buildRenamePreview(files, pattern, options = {}) {
  const { counter = 1, step = 1, zeroPad = 3 } = options;
  let count = counter;

  return files.map((filePath) => {
    const ext = path.extname(filePath);
    const base = path.basename(filePath, ext);
    const dir = path.dirname(filePath);

    let newName = pattern
      .replace(/\{name\}/g, base)
      .replace(/\{ext\}/g, ext.slice(1))
      .replace(/\{counter\}/g, String(count).padStart(zeroPad, '0'))
      .replace(/\{date\}/g, new Date().toISOString().split('T')[0])
      .replace(/\{upper\}/g, base.toUpperCase())
      .replace(/\{lower\}/g, base.toLowerCase());

    count += step;

    return {
      original: filePath,
      renamed: path.join(dir, newName + ext),
      preview: newName + ext,
    };
  });
}

function resolveConflict(source, dest, strategy = 'ask') {
  const strategies = {
    overwrite: () => ({ action: 'overwrite' }),
    skip: () => ({ action: 'skip' }),
    rename: () => {
      const ext = path.extname(dest);
      const base = path.basename(dest, ext);
      const dir = path.dirname(dest);
      const timestamp = Date.now();
      return {
        action: 'rename',
        newPath: path.join(dir, `${base}_${timestamp}${ext}`),
      };
    },
    ask: () => ({ action: 'prompt', source, dest }),
  };

  return (strategies[strategy] || strategies.ask)();
}

module.exports = {
  FileOperationQueue,
  computeFileHash,
  findDuplicates,
  buildRenamePreview,
  resolveConflict,
  CHUNK_SIZE,
  COPY_BUFFER_SIZE,
};
