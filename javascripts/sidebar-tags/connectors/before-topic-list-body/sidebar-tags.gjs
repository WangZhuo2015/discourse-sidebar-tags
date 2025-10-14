import Component from "@ember/component";
import { tagName } from "@ember-decorators/component";
import discourseTag from "discourse/helpers/discourse-tag";
import { ajax } from "discourse/lib/ajax";
import { getOwnerWithFallback } from "discourse/lib/get-owner";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import { scheduleOnce } from "@ember/runloop";

function alphaId(a, b) {
  if (a.id < b.id) return -1;
  if (a.id > b.id) return 1;
  return 0;
}

function tagCount(a, b) {
  if (a.count > b.count) return -1;
  if (a.count < b.count) return 1;
  return 0;
}

// 唯一标识符
const TAG_BAR_ID = "discourse-sidebar-tags-instance";

@tagName("")
export default class SidebarTags extends Component {
  init() {
    super.init(...arguments);
    this.setProperties({
      hideSidebar: true,
      isDiscoveryList: false,
      tagList: [],
      category: null
    });

    if (!this.site.mobileView) {
      withPluginApi((api) => {
        api.onPageChange((url) => {
          const tagRegex = /^\/tag[s]?\/(.*)/;
          if (!settings.enable_tag_cloud) return;

          // ✅ 关键：每次 onPageChange 都先清理旧的标签栏（防止重复）
          this._removeTagBar();

          this.setProperties({
            isDiscoveryList: false,
            hideSidebar: true,
            tagList: [],
            category: null
          });

          if (this.discoveryList || url.match(tagRegex)) {
            if (this.isDestroyed || this.isDestroying) return;
            this.set("isDiscoveryList", true);

            ajax("/tags.json").then((result) => {
              if (this.isDestroyed || this.isDestroying) return;

              const tagGroups = result.extras?.tag_groups || [];
              const allTags = result.tags || [];
              let foundTags = [];

              const getAllTagsFromGroups = (groups) => {
                return groups.flatMap(group => group.tags || []);
              };

              if (url.match(/^\/c\/(.*)/)) {
                const controller = getOwnerWithFallback(this).lookup("controller:navigation/category");
                const category = controller?.get("category");
                if (!category) {
                  this.set("hideSidebar", true);
                  return;
                }
                this.set("category", category);

                const allowedTagNames = new Set(category.allowed_tags || []);
                const allowedGroupNames = new Set(category.allowed_tag_groups || []);
                const allowedTags = [];

                if (allowedTagNames.size > 0) {
                  allTags.forEach(tag => {
                    if (allowedTagNames.has(tag.name)) allowedTags.push(tag);
                  });
                }
                if (allowedGroupNames.size > 0) {
                  tagGroups.forEach(group => {
                    if (allowedGroupNames.has(group.name)) {
                      allowedTags.push(...(group.tags || []));
                    }
                  });
                }

                const seen = new Set();
                const uniqueAllowedTags = allowedTags.filter(tag => {
                  if (seen.has(tag.name)) return false;
                  seen.add(tag.name);
                  return true;
                });

                if (uniqueAllowedTags.length > 0) {
                  this.set("hideSidebar", false);
                  foundTags = settings.sort_by_popularity
                    ? uniqueAllowedTags.sort(tagCount)
                    : uniqueAllowedTags.sort(alphaId);
                } else {
                  this.set("hideSidebar", true);
                }
              } else {
                this.set("hideSidebar", false);
                let allGroupTags = getAllTagsFromGroups(tagGroups);
                if (allGroupTags.length === 0) allGroupTags = allTags;
                foundTags = settings.sort_by_popularity
                  ? allGroupTags.sort(tagCount)
                  : allGroupTags.sort(alphaId);
              }

              if (!(this.isDestroyed || this.isDestroying)) {
                this.set("tagList", foundTags.slice(0, settings.number_of_tags));
                scheduleOnce("afterRender", this, "moveToTopOfTable");
              }
            });
          }
        });
      });
    }
  }

  moveToTopOfTable() {
    if (this.isDestroyed || this.isDestroying || this.hideSidebar) {
      this._removeTagBar();
      return;
    }

    const table = document.querySelector(".topic-list");
    if (!table || !table.parentNode) {
      this._removeTagBar();
      return;
    }

    let tagBar = document.getElementById(TAG_BAR_ID);
    if (!tagBar) {
      // 如果 Glimmer 渲染的元素没有 ID，我们手动找并加 ID
      tagBar = document.querySelector(".discourse-sidebar-tags");
      if (tagBar) {
        tagBar.id = TAG_BAR_ID;
      } else {
        return; // 未渲染
      }
    }

    // 确保只插入一次：检查是否已在正确位置
    if (tagBar.parentNode === table.parentNode && tagBar.nextSibling === table) {
      return;
    }

    // 插入到 table 前面
    table.parentNode.insertBefore(tagBar, table);
  }

  _removeTagBar() {
    const existing = document.getElementById(TAG_BAR_ID) || document.querySelector(".discourse-sidebar-tags");
    if (existing) existing.remove();
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this._removeTagBar();
  }

  <template>
    {{#unless this.site.mobileView}}
      {{#if this.isDiscoveryList}}
        {{#unless this.hideSidebar}}
          {{!-- 添加唯一 ID，便于识别 --}}
          <div id={{TAG_BAR_ID}} class="discourse-sidebar-tags">
            <div class="sidebar-tags-list">
              <h3 class="tags-list-title">
                {{i18n (themePrefix "tag_sidebar.title")}}
              </h3>
              {{#if this.tagList.length}}
                {{#each this.tagList as |t|}}
                  {{discourseTag t.id style="box"}}
                {{/each}}
              {{else}}
                <p class="no-tags">{{i18n (themePrefix "tag_sidebar.no_tags")}}</p>
              {{/if}}
            </div>
          </div>
        {{/unless}}
      {{/if}}
    {{/unless}}
  </template>
}