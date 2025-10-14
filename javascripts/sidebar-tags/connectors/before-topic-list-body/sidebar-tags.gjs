import Component from "@ember/component";
import { tagName } from "@ember-decorators/component";
import discourseTag from "discourse/helpers/discourse-tag";
import { ajax } from "discourse/lib/ajax";
import { getOwnerWithFallback } from "discourse/lib/get-owner";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

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

@tagName("")
export default class SidebarTags extends Component {
  init() {
    super.init(...arguments);
    // 初始隐藏
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

          // 重置状态：每次页面变化都先隐藏并清空
          this.setProperties({
            isDiscoveryList: false,
            hideSidebar: true,
            tagList: [],
            category: null
          });

          if (this.discoveryList || url.match(tagRegex)) {
            if (this.isDestroyed || this.isDestroying) return;

            this.set("isDiscoveryList", true);

            // 发起请求
            ajax("/tags.json").then((result) => {
              if (this.isDestroyed || this.isDestroying) return;

              const tagGroups = result.extras?.tag_groups || [];
              const allTags = result.tags || [];
              let foundTags = [];

              const getAllTagsFromGroups = (groups) => {
                return groups.flatMap(group => group.tags || []);
              };

              if (url.match(/^\/c\/(.*)/)) {
                // 分类页面
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
                    if (allowedTagNames.has(tag.name)) {
                      allowedTags.push(tag);
                    }
                  });
                }

                if (allowedGroupNames.size > 0) {
                  tagGroups.forEach(group => {
                    if (allowedGroupNames.has(group.name)) {
                      allowedTags.push(...(group.tags || []));
                    }
                  });
                }

                // 去重
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
                  // 无允许标签 → 隐藏
                  this.set("hideSidebar", true);
                  return;
                }
              } else {
                // 非分类页：显示所有 tag group 标签
                this.set("hideSidebar", false);
                let allGroupTags = getAllTagsFromGroups(tagGroups);
                if (allGroupTags.length === 0) allGroupTags = allTags;
                foundTags = settings.sort_by_popularity
                  ? allGroupTags.sort(tagCount)
                  : allGroupTags.sort(alphaId);
              }

              if (!(this.isDestroyed || this.isDestroying)) {
                this.set("tagList", foundTags.slice(0, settings.number_of_tags));
              }
            });
          }
        });
      });
    }
  }

  <template>
    {{#unless this.site.mobileView}}
      {{#if this.isDiscoveryList}}
        {{#unless this.hideSidebar}}
          <div class="discourse-sidebar-tags">
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