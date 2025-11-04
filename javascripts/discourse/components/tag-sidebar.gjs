import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import bodyClass from "discourse/helpers/body-class";
import discourseTag from "discourse/helpers/discourse-tag";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";

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

export default class TagSidebar extends Component {
  @service router;
  @service site;

  @tracked tagList = [];
  @tracked shouldDisplay = false;
  @tracked category = null;

  get currentCategory() {
    return this.router.currentRoute?.attributes?.category;
  }
  
  get isDiscoveryRoute() {
    const routeName = this.router.currentRouteName || "";
    return routeName.startsWith("discovery.") || routeName.startsWith("tags.show");
  }

  @action
  async loadTags() {
    console.log("--- [TagSidebar] loadTags action started ---");

    this.shouldDisplay = false;
    this.tagList = [];
    this.category = null;

    if (this.site.mobileView) {
      console.log("[TagSidebar] Exit: Is mobile view.");
      return;
    }
    if (!settings.enable_tag_cloud) {
      console.log("[TagSidebar] Exit: 'enable_tag_cloud' setting is not checked.");
      return;
    }
    if (!this.isDiscoveryRoute) {
      console.log(`[TagSidebar] Exit: Not a discovery route. Current route: ${this.router.currentRouteName}`);
      return;
    }
    
    const category = this.currentCategory;
    console.log("[TagSidebar] Current category object:", category);

    if (!category) {
      console.log("[TagSidebar] Exit: No category found on current route.");
      return;
    }
    
    const hasSubcategories = category.subcategories && category.subcategories.length > 0;
    if (hasSubcategories) {
        console.log(`[TagSidebar] Exit: Category '${category.name}' has subcategories.`);
        return;
    }

    this.category = category;

    try {
      const tagsResult = await ajax("/tags.json");

      const tagGroups = tagsResult.extras?.tag_groups || [];
      const allTagsInGroups = tagGroups.flatMap(g => g.tags || []);
      const allRootTags = tagsResult.tags || [];

      const allTagsMap = new Map(
        [...allTagsInGroups, ...allRootTags].map(tag => [tag.id, tag])
      );
      const allTags = Array.from(allTagsMap.values());

      const allowedTagNames = new Set(category.allowed_tags || []);
      const allowedGroupNames = new Set(category.allowed_tag_groups || []);
      console.log(`[TagSidebar] For category '${category.name}': Allowed tags:`, Array.from(allowedTagNames), "Allowed tag groups:", Array.from(allowedGroupNames));


      if (allowedTagNames.size === 0 && allowedGroupNames.size === 0) {
        console.log("[TagSidebar] Exit: No 'allowed_tags' or 'allowed_tag_groups' configured for this category.");
        return;
      }
      
      const allowedTags = [];

      if (allowedTagNames.size > 0) {
        allTags.forEach(tag => {
          if (allowedTagNames.has(tag.id)) {
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
      
      console.log("[TagSidebar] Found matching raw tags (before deduplication):", allowedTags.map(t => t.id));

      const seen = new Set();
      const uniqueAllowedTags = allowedTags.filter(tag => {
        if (seen.has(tag.id)) return false;
        seen.add(tag.id);
        return true;
      });
      console.log("[TagSidebar] Unique allowed tags (after deduplication):", uniqueAllowedTags.map(t => t.id));


      if (uniqueAllowedTags.length > 0) {
        const sortedTags = settings.sort_by_popularity
          ? uniqueAllowedTags.sort(tagCount)
          : uniqueAllowedTags.sort(alphaId);
        
        this.tagList = sortedTags.slice(0, settings.number_of_tags);
        this.shouldDisplay = true;
        console.log(`[TagSidebar] SUCCESS: Component will be displayed. Final tags list (max ${settings.number_of_tags}):`, this.tagList);
      } else {
        console.log("[TagSidebar] Exit: No unique tags were left after processing. Nothing to display.");
      }

    } catch (error) {
      console.error("[TagSidebar] ERROR: An error occurred during tag loading:", error);
      this.shouldDisplay = false;
    }
  }

  <template>
    {{! v1. 创建一个始终存在的、不可见的 "控制器" 元素 }}
    {{! v2. 将生命周期钩子(didInsert/didUpdate)绑定到这个元素上 }}
    <div
      class="tag-sidebar-manager-do-not-style"
      {{didInsert this.loadTags}}
      {{didUpdate this.loadTags this.currentCategory}}
    ></div>

    {{! v3. 保持原有的显示逻辑不变 }}
    {{#if this.shouldDisplay}}
      {{bodyClass "tag-sidebar-active"}}

      <div class="discourse-sidebar-tags">
        <div class="sidebar-tags-list">
          <h3 class="tags-list-title">
            {{i18n (themePrefix "tag_sidebar.title")}}
          </h3>
          {{#if this.tagList.length}}
            {{#each this.tagList as |t|}}
              <a href="/tags/c/{{this.category.slug}}/{{this.category.id}}/{{t.id}}" class="discourse-tag box">{{t.id}}</a>
            {{/each}}
          {{else}}
            <p class="no-tags">{{i18n (themePrefix "tag_sidebar.no_tags")}}</p>
          {{/if}}
        </div>
      </div>
    {{/if}}
  </template>
}
