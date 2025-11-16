#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// package.jsonを読み込み
const packageJsonPath = join(__dirname, 'package.json');
const packageJson = JSON.parse(readFileSync(packageJsonPath, 'utf8'));

// 現在のバージョンを取得
const currentVersion = packageJson.version;
const versionParts = currentVersion.split('.');

// patchバージョンをインクリメント
const major = parseInt(versionParts[0], 10);
const minor = parseInt(versionParts[1], 10);
const patch = parseInt(versionParts[2], 10) + 1;

const newVersion = `${major}.${minor}.${patch}`;

console.log(`📦 Updating version: ${currentVersion} → ${newVersion}`);

// package.jsonを更新
packageJson.version = newVersion;
writeFileSync(packageJsonPath, JSON.stringify(packageJson, null, 2) + '\n');
console.log(`✅ Updated package.json`);

// tauri.conf.jsonを更新
const tauriConfigPath = join(__dirname, 'src-tauri', 'tauri.conf.json');
const tauriConfig = JSON.parse(readFileSync(tauriConfigPath, 'utf8'));
tauriConfig.version = newVersion;
writeFileSync(tauriConfigPath, JSON.stringify(tauriConfig, null, 2) + '\n');
console.log(`✅ Updated tauri.conf.json`);

console.log(`🎉 Version updated to ${newVersion}`);
