import Component from "@ember/component";
import { tagName } from "@ember-decorators/component";
import { ajax } from "discourse/lib/ajax";
import { service } from "@ember/service";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import { scheduleOnce, debounce } from "@ember/runloop";
import { action } from "@ember/object";
import { on } from '@ember/modifier';
import { get } from "@ember/object";
import { fn } from '@ember/helper';

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

const TAG_BAR_ID = "discourse-sidebar-tags-instance";
const UNCATEGORIZED_KEY = "_uncategorized";

@tagName("")
export default class SidebarTags extends Component {
  @service discovery;
  get = get;

  init() {
    super.init(...arguments);
    this.setProperties({
      hideSidebar: true,
      isDiscoveryList: false,
      tagList: [],
      category: null,
      tagsExpanded: false,
      isOverflowing: false,
      groupedTagList: [],
      groupExpansionStates: {}, 
      groupOverflowStates: {} 
    });

    if (!this.site.mobileView) {
      withPluginApi((api) => {
        api.onPageChange((url) => {
          const tagRegex = /^\/tag[s]?\/(.*)/;
          if (!settings.enable_tag_cloud) return;

          this._removeTagBar();

          this.setProperties({
            isDiscoveryList: false,
            hideSidebar: true,
            tagList: [],
            category: null,
            tagsExpanded: false,
            isOverflowing: false,
            groupedTagList: [],
            groupExpansionStates: {},
            groupOverflowStates: {}
          });

          if (this.discoveryList || url.match(tagRegex)) {
            if (this.isDestroyed || this.isDestroying) return;
            this.set("isDiscoveryList", true);

            ajax("/tags.json").then((result) => {
              if (this.isDestroyed || this.isDestroying) return;
              this._processTags(url, result);
            });
          }
        });
      });
    }
  }

  // [新逻辑] 对 _processTags 函数进行了重构以支持分类过滤
  _processTags(url, result) {
      const allApiTagGroups = result.extras?.tag_groups || [];
      const allApiTags = result.tags || [];
      
      let sourceTagGroups = []; // 要处理的标签组数据源
      let sourceIndividualTags = []; // 要处理的独立标签数据源

      // 判断是否在分类页面
      if (url.match(/^\/c\/(.*)/)) {
        const category = this.discovery.category;
        
        if (!category) {
          this.set("hideSidebar", true);
          return;
        }
        this.set("category", category);

        const allowedGroupNames = new Set(category.allowed_tag_groups || []);
        const allowedTagNames = new Set(category.allowed_tags || []);

        // 1. 筛选出分类允许的标签组
        if (allowedGroupNames.size > 0) {
            sourceTagGroups = allApiTagGroups.filter(group => allowedGroupNames.has(group.name));
        }

        // 2. 筛选出分类允许的单个标签
        if (allowedTagNames.size > 0) {
            sourceIndividualTags = allApiTags.filter(tag => allowedTagNames.has(tag.name));
        }

        // 如果该分类下没有任何允许的标签或标签组，则不显示组件
        if (sourceTagGroups.length === 0 && sourceIndividualTags.length === 0) {
          this.set("hideSidebar", true);
          return;
        }

      } else {
        // [新逻辑] 在非分类页面，使用全部标签和标签组作为数据源
        sourceTagGroups = allApiTagGroups;
        sourceIndividualTags = allApiTags;
      }
      
      this.set("hideSidebar", false);

      // [新逻辑] 后续处理全部基于上面确定的 sourceTagGroups 和 sourceIndividualTags
      if (settings.group_tags_by_tag_group) {
        const processedGroups = [];
        const expansionStates = {};
        const overflowStates = {};
        
        const allGroupedTagIds = new Set();
        
        // 处理标签组
        sourceTagGroups.forEach(group => {
          if (group.tags && group.tags.length > 0) {
            group.tags.forEach(t => allGroupedTagIds.add(t.id));

            const groupKey = group.name.replace(/[^a-zA-Z0-9]/g, "_");
            processedGroups.push({
              key: groupKey,
              name: group.name,
              tags: group.tags.sort(alphaId)
            });
            expansionStates[groupKey] = false;
            overflowStates[groupKey] = false;
          }
        });
        
        // [新逻辑] “其他标签”现在由不属于任何已显示标签组的 sourceIndividualTags 构成
        const uncategorizedTags = sourceIndividualTags.filter(tag => !allGroupedTagIds.has(tag.id));
        
        if (uncategorizedTags.length > 0) {
            processedGroups.push({
                key: UNCATEGORIZED_KEY,
                name: i18n(themePrefix("tag_sidebar.uncategorized_tags")),
                tags: uncategorizedTags.sort(alphaId)
            });
            expansionStates[UNCATEGORIZED_KEY] = false;
            overflowStates[UNCATEGORIZED_KEY] = false;
        }
        
        this.setProperties({
            groupedTagList: processedGroups,
            groupExpansionStates: expansionStates,
            groupOverflowStates: overflowStates
        });

      } else {
        // [新逻辑] 平铺模式也使用新的数据源
        const sortFn = settings.sort_by_popularity ? tagCount : alphaId;
        const allGroupTags = sourceTagGroups.flatMap(group => group.tags || []);
        
        // 合并并去重
        const combinedTags = [...allGroupTags, ...sourceIndividualTags];
        const uniqueTags = Array.from(new Map(combinedTags.map(t => [t.id, t])).values());

        this.set("tagList", uniqueTags.sort(sortFn).slice(0, settings.number_of_tags));
      }

      scheduleOnce("afterRender", this, "moveToTopOfTable");
      scheduleOnce("afterRender", this, "checkTagOverflow");
  }

  didInsertElement() {
    super.didInsertElement(...arguments);
    this._resizeListener = () => debounce(this, this.checkTagOverflow, 150);
    window.addEventListener("resize", this._resizeListener);
  }

  getTagUrl(tagName) {
    const path = window.location.pathname;
    const match = path.match(/^\/(?:tags\/c|c)\/([^\/]+)\/(\d+)/);
    if (match) {
      const slug = match[1];
      const categoryId = match[2];
      return `/tags/c/${slug}/${categoryId}/${tagName}`;
    }
    return `/tag/${tagName}`;
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
      tagBar = document.querySelector(".discourse-sidebar-tags");
      if (tagBar) {
        tagBar.id = TAG_BAR_ID;
      } else {
        return;
      }
    }

    if (tagBar.parentNode === table.parentNode && tagBar.nextSibling === table) {
      return;
    }

    table.parentNode.insertBefore(tagBar, table);
  }

  checkTagOverflow() {
    if (this.isDestroyed || this.isDestroying) {
      return;
    }

    if (settings.group_tags_by_tag_group) {
        this.groupedTagList.forEach(group => {
            const list = document.querySelector(`[data-group-key="${group.key}"] .sidebar-tags-list`);
            if (list && !this.groupExpansionStates[group.key]) {
                const isOverflowing = list.scrollWidth > list.clientWidth;
                if (this.groupOverflowStates[group.key] !== isOverflowing) {
                    this.set(`groupOverflowStates.${group.key}`, isOverflowing);
                }
            }
        });
    } else {
        const list = document.querySelector(`#${TAG_BAR_ID} .sidebar-tags-list`);
        if (list && !this.tagsExpanded) {
          const isOverflowing = list.scrollWidth > list.clientWidth;
          if (this.isOverflowing !== isOverflowing) {
            this.set("isOverflowing", isOverflowing);
          }
        }
    }
  }

  @action
  toggleExpand(event) {
    event.preventDefault();
    this.toggleProperty("tagsExpanded");
  }
  
  @action
  toggleGroupExpand(groupKey, event) {
    event.preventDefault();
    this.set(`groupExpansionStates.${groupKey}`, !this.groupExpansionStates[groupKey]);
  }

  _removeTagBar() {
    const existing = document.getElementById(TAG_BAR_ID) || document.querySelector(".discourse-sidebar-tags");
    if (existing) existing.remove();
  }

  willDestroy() {
    if (this._resizeListener) {
      window.removeEventListener("resize", this._resizeListener);
    }
    super.willDestroy(...arguments);
    this._removeTagBar();
  }

  <template>
    {{#unless this.site.mobileView}}
      {{#if this.isDiscoveryList}}
        {{#unless this.hideSidebar}}
          <div id={{TAG_BAR_ID}} class="discourse-sidebar-tags">
            {{#if settings.group_tags_by_tag_group}}
              {{! Grouped View }}
              {{#each this.groupedTagList as |group|}}
                <div 
                  class="sidebar-tag-group-row {{if (get this.groupExpansionStates group.key) "is-expanded"}}"
                  data-group-key={{group.key}}
                >
                  <div class="sidebar-tags-list-wrapper">
                    <div class="sidebar-tags-list">
                      <h3 class="tags-list-title">
                        {{group.name}}
                      </h3>
                      {{#if group.tags.length}}
                        {{#each group.tags as |t|}}
                          <a
                            href={{this.getTagUrl t.name}}
                            data-tag-name={{t.name}}
                            class="discourse-tag box"
                          >
                            {{t.name}}
                          </a>
                        {{/each}}
                      {{else}}
                        <p class="no-tags">{{i18n (themePrefix "tag_sidebar.no_tags")}}</p>
                      {{/if}}
                    </div>

                    {{#if (get this.groupOverflowStates group.key)}}
                      <a href class="tags-expand-btn" {{on "click" (fn this.toggleGroupExpand group.key)}}>
                        {{#if (get this.groupExpansionStates group.key)}}
                          {{i18n (themePrefix "tag_sidebar.collapse")}}
                        {{else}}
                          ...
                        {{/if}}
                      </a>
                    {{/if}}
                  </div>
                </div>
              {{/each}}
            {{else}}
              {{! Original Flat View }}
              <div class="sidebar-tag-group-row {{if this.tagsExpanded "is-expanded"}}">
                <div class="sidebar-tags-list-wrapper">
                  <div class="sidebar-tags-list">
                    <h3 class="tags-list-title">
                      {{i18n (themePrefix "tag_sidebar.title")}}
                    </h3>
                    {{#if this.tagList.length}}
                      {{#each this.tagList as |t|}}
                        <a
                          href={{this.getTagUrl t.name}}
                          data-tag-name={{t.name}}
                          class="discourse-tag box"
                        >
                          {{t.name}}
                        </a>
                      {{/each}}
                    {{else}}
                      <p class="no-tags">{{i18n (themePrefix "tag_sidebar.no_tags")}}</p>
                    {{/if}}
                  </div>

                  {{#if this.isOverflowing}}
                    <a href class="tags-expand-btn" {{on "click" this.toggleExpand}}>
                      {{#if this.tagsExpanded}}
                        {{i18n (themePrefix "tag_sidebar.collapse")}}
                      {{else}}
                        ...
                      {{/if}}
                    </a>
                  {{/if}}
                </div>
              </div>
            {{/if}}
          </div>
        {{/unless}}
      {{/if}}
    {{/unless}}
  </template>
}
