import Component from "@ember/component";
import { tagName } from "@ember-decorators/component";
import discourseTag from "discourse/helpers/discourse-tag";
import { ajax } from "discourse/lib/ajax";
import { service } from "@ember/service";
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
  @service discovery;

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

              ajax("/tags.json").then((tagsResult) => {
                if (this.isDestroyed || this.isDestroying) return;

                const tagGroups = tagsResult.extras?.tag_groups || [];
                const allTagsInGroups = tagGroups.flatMap(g => g.tags || []);
                const allRootTags = tagsResult.tags || [];

                // Combine and deduplicate tags based on 'id'
                const allTagsMap = new Map(
                  [...allTagsInGroups, ...allRootTags].map(tag => [tag.id, tag])
                );
                const allTags = Array.from(allTagsMap.values());

                let foundTags = [];

                const getAllTagsFromGroups = (groups) => {
                  return groups.flatMap(group => group.tags || []);
                };

                const category = this.discovery.category;

                if (!category) {
                  document.querySelector(".topic-list")?.classList.remove("with-sidebar");
                  return;
                }
                
                const hasSubcategories = category.subcategories && category.subcategories.length > 0;
                if (hasSubcategories) {
                    this.set("hideSidebar", true);
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
                
                console.log("Found tags to be rendered:", foundTags);
                if (!(this.isDestroyed || this.isDestroying)) {
                  this.set("tagList", foundTags.slice(0, settings.number_of_tags));
                  // 在这里添加日志，检查 hideSidebar 的状态
                  console.log("Final hideSidebar state:", this.get("hideSidebar"));
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
                  {{#if this.category}}
                    <a href="/tags{{this.category.url}}/{{t.id}}" class="discourse-tag box">{{t.id}}</a>
                  {{else}}
                    {{discourseTag t.id style="box"}}
                  {{/if}}
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
