import Component from "@ember/component";
import { tagName } from "@ember-decorators/component";
import discourseTag from "discourse/helpers/discourse-tag";
import { ajax } from "discourse/lib/ajax";
import { getOwnerWithFallback } from "discourse/lib/get-owner";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

function alphaId(a, b) {
  if (a.id < b.id) {
    return -1;
  }
  if (a.id > b.id) {
    return 1;
  }
  return 0;
}

function tagCount(a, b) {
  if (a.count > b.count) {
    return -1;
  }
  if (a.count < b.count) {
    return 1;
  }
  return 0;
}

@tagName("")
export default class SidebarTags extends Component {
  init() {
    super.init(...arguments);
    this.set("hideSidebar", true);
    document.querySelector(".topic-list")?.classList.add("with-sidebar");

    if (!this.site.mobileView) {
      withPluginApi((api) => {
        api.onPageChange((url) => {
          const tagRegex = /^\/tag[s]?\/(.*)/;
          if (settings.enable_tag_cloud) {
            if (this.discoveryList || url.match(tagRegex)) {
              if (this.isDestroyed || this.isDestroying) {
                return;
              }
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
                  // 分类页面
                  const controller = getOwnerWithFallback(this).lookup(
                    "controller:navigation/category"
                  );
                  const category = controller?.get("category");

                  if (!category) {
                    document.querySelector(".topic-list")?.classList.remove("with-sidebar");
                    return;
                  }

                  this.set("category", category);

                  const allowedTagNames = new Set(category.allowed_tags || []);
                  const allowedGroupNames = new Set(category.allowed_tag_groups || []);

                  const allowedTags = [];

                  // 1. 从 allowed_tags 添加
                  if (allowedTagNames.size > 0) {
                    allTags.forEach(tag => {
                      if (allowedTagNames.has(tag.name)) {
                        allowedTags.push(tag);
                      }
                    });
                  }

                  // 2. 从 allowed_tag_groups 添加
                  if (allowedGroupNames.size > 0) {
                    tagGroups.forEach(group => {
                      if (allowedGroupNames.has(group.name)) {
                        allowedTags.push(...(group.tags || []));
                      }
                    });
                  }

                  // 去重（按 name）
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
                    document.querySelector(".topic-list")?.classList.remove("with-sidebar");
                    return;
                  }
                } else {
                  // 非分类页面：显示所有 tag group 中的标签
                  this.set("hideSidebar", false);
                  let allGroupTags = getAllTagsFromGroups(tagGroups);
                  // 如果没有 tag groups，回退到全部标签
                  if (allGroupTags.length === 0) {
                    allGroupTags = allTags;
                  }
                  foundTags = settings.sort_by_popularity
                    ? allGroupTags.sort(tagCount)
                    : allGroupTags.sort(alphaId);
                }

                if (!(this.isDestroyed || this.isDestroying)) {
                  this.set("tagList", foundTags.slice(0, settings.number_of_tags));
                }
              });
            } else {
              this.set("isDiscoveryList", false);
            }
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