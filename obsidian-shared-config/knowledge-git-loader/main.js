const { Plugin } = require("obsidian");
const path = require("path");

// 共享配置下所有 Vault 共用同一份 community-plugins.json，Git 插件一旦启用就会
// 出现在每一个 Vault 里，给它们都建仓库。这里按 data.json 的 vaults 白名单
// 只放行指定的 Vault，其余 Vault 里 Git 插件保持不加载。
module.exports = class KnowledgeGitLoader extends Plugin {
  async onload() {
    const settings = (await this.loadData()) || {};
    const vaults = Array.isArray(settings.vaults) ? settings.vaults : [];
    const current = path.resolve(this.app.vault.adapter.getBasePath()).toLowerCase();

    this.allowed = vaults.some(item =>
      typeof item === "string" && path.resolve(item).toLowerCase() === current);
    if (!this.allowed) return;

    if (!this.app.plugins.plugins["obsidian-git"] &&
        !await this.app.plugins.enablePlugin("obsidian-git")) {
      throw new Error("Knowledge Git Loader: could not load obsidian-git");
    }
  }

  async onunload() {
    if (this.allowed) await this.app.plugins.disablePlugin("obsidian-git");
  }
};
