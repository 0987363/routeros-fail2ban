import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const script = readFileSync(new URL('../routeros-login-guard.rsc', import.meta.url), 'utf8');
const readme = readFileSync(new URL('../README.md', import.meta.url), 'utf8');

test('终端安装脚本仅包含可打印 ASCII、换行和制表符', () => {
  const invalid = script.split('\n').flatMap((line, index) =>
    /[^\x09\x0D\x20-\x7E]/.test(line) ? [index + 1] : []);
  assert.deepEqual(invalid, [], `非 ASCII 内容位于第 ${invalid.join(', ')} 行，可能在终端粘贴时损坏`);
});

test('README 中所有 RouterOS 命令都满足相同的粘贴字符约束', () => {
  const blocks = [...readme.matchAll(/```routeros\n([\s\S]*?)\n```/g)];
  assert(blocks.length > 0, '未找到 RouterOS 命令块');
  for (const [index, block] of blocks.entries()) {
    assert(!/[^\x09\x0A\x0D\x20-\x7E]/.test(block[1]), `第 ${index + 1} 个命令块含非 ASCII 字符`);
  }
});

test('独立卸载脚本满足终端粘贴字符约束', () => {
  const path = new URL('../routeros-login-guard-uninstall.rsc', import.meta.url);
  assert(existsSync(path), '缺少独立卸载脚本');
  const uninstall = readFileSync(path, 'utf8');
  assert(!/[^\x09\x0A\x0D\x20-\x7E]/.test(uninstall), '卸载脚本含非 ASCII 字符');
});
