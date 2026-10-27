// knowledge-git-loader 自检：验证围栏逻辑（哪些 Vault 才加载 obsidian-git）。
// 用法：
//   node knowledge-git-loader.test.cjs [插件目录] [共享配置目录]
// 两个参数都可省略：插件目录默认脚本旁的 knowledge-git-loader，
// 共享配置目录给定时会额外校验 data.json / community-plugins.json 的一致性。
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const pluginDir = process.argv[2] || path.join(__dirname, "knowledge-git-loader");
const configDir = process.argv[3] || "";

function loadPlugin(source) {
  const context = {
    module: { exports: {} },
    require: name => (name === "obsidian" ? { Plugin: class {} } : require(name)),
  };
  vm.runInNewContext(source, context);
  return context.module.exports;
}

const PluginClass = loadPlugin(fs.readFileSync(path.join(pluginDir, "main.js"), "utf8"));

async function check(vaults, vaultPath, expectAllowed, enableSucceeds = true) {
  const calls = [];
  const loader = new PluginClass();
  loader.loadData = async () => (vaults === undefined ? undefined : { vaults });
  loader.app = {
    vault: { adapter: { getBasePath: () => vaultPath } },
    plugins: {
      plugins: {},
      enablePlugin: async id => { calls.push(["enable", id]); return enableSucceeds; },
      disablePlugin: async id => { calls.push(["disable", id]); },
    },
  };

  if (expectAllowed && !enableSucceeds) {
    await assert.rejects(loader.onload(), /could not load obsidian-git/);
    return;
  }
  await loader.onload();
  await loader.onunload();
  assert.deepEqual(calls, expectAllowed
    ? [["enable", "obsidian-git"], ["disable", "obsidian-git"]]
    : []);
}

(async () => {
  const vaults = ["D:\\vault-a", "D:\\vault-b"];

  await check(vaults, "D:\\vault-a", true);
  await check(vaults, "d:\\VAULT-A\\", true);        // 大小写 / 尾斜杠
  await check(vaults, "D:\\vault-b", true);          // 白名单第二个
  await check(vaults, "D:\\vault-c", false);         // 不在白名单
  await check(vaults, "D:\\vault-a-copy", false);    // 前缀相似不算命中
  await check(vaults, "E:\\vault-a", false);         // 其他盘符
  await check([], "D:\\vault-a", false);             // 白名单为空
  await check(undefined, "D:\\vault-a", false);      // 没有 data.json
  await check(vaults, "D:\\vault-a", true, false);   // 启用失败必须抛错

  if (configDir) {
    const dataFile = path.join(configDir, "plugins", "knowledge-git-loader", "data.json");
    assert.ok(fs.existsSync(dataFile), `缺少白名单配置: ${dataFile}`);
    const settings = JSON.parse(fs.readFileSync(dataFile, "utf8"));
    assert.ok(Array.isArray(settings.vaults) && settings.vaults.length > 0,
      "data.json 的 vaults 必须是非空数组");

    const enabled = JSON.parse(fs.readFileSync(path.join(configDir, "community-plugins.json"), "utf8"));
    assert.ok(enabled.includes("knowledge-git-loader"), "围栏插件必须启用");
    assert.ok(!enabled.includes("obsidian-git"), "obsidian-git 不能出现在全局启用列表");
  }

  console.log(`Knowledge Git Loader: 9 checks passed${configDir ? " + config check" : ""}`);
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
